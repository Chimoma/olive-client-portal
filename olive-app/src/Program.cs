using System.Text.Json;
using Microsoft.Data.SqlClient;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// ---------------------------------------------------------------------
// Connection string resolution:
//   - In ECS, the "DB_CREDENTIALS" secret is injected as a JSON string
//     (see terraform/secrets.tf) with host/username/password/dbname.
//   - Locally, falls back to appsettings.json / env vars for dev testing.
// ---------------------------------------------------------------------
string GetConnectionString()
{
    var raw = Environment.GetEnvironmentVariable("DB_CREDENTIALS");
    if (!string.IsNullOrEmpty(raw))
    {
        var creds = JsonSerializer.Deserialize<JsonElement>(raw);
        var host = creds.GetProperty("host").GetString();
        var port = creds.GetProperty("port").GetInt32();
        var user = creds.GetProperty("username").GetString();
        var pass = creds.GetProperty("password").GetString();
        var db   = creds.GetProperty("dbname").GetString();
        return $"Server={host},{port};Database={db};User Id={user};Password={pass};TrustServerCertificate=True;";
    }

    // Local development fallback
    return builder.Configuration.GetConnectionString("OliveDb")
        ?? "Server=localhost,1433;Database=olive;User Id=sa;Password=DevOnly_Password1!;TrustServerCertificate=True;";
}

// Simple health check - used by the ALB target group health check
app.MapGet("/", () => Results.Ok(new { status = "healthy", app = "olive-client-portal" }));

// Confirms the app can actually reach the migrated database
app.MapGet("/api/health/db", async () =>
{
    try
    {
        await using var conn = new SqlConnection(GetConnectionString());
        await conn.OpenAsync();
        return Results.Ok(new { database = "connected" });
    }
    catch (Exception ex)
    {
        return Results.Problem($"Database connection failed: {ex.Message}");
    }
});

// Reads the "Customers" table - this is the data migrated from the legacy
// database via DMS (see db/legacy-schema-seed.sql and terraform/dms.tf)
app.MapGet("/api/customers", async () =>
{
    var customers = new List<object>();

    await using var conn = new SqlConnection(GetConnectionString());
    await conn.OpenAsync();

    await using var cmd = new SqlCommand("SELECT Id, Name, Email, CreatedAt FROM Customers ORDER BY Id", conn);
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        customers.Add(new
        {
            Id = reader.GetInt32(0),
            Name = reader.GetString(1),
            Email = reader.GetString(2),
            CreatedAt = reader.GetDateTime(3)
        });
    }

    return Results.Ok(customers);
});

app.Run("http://0.0.0.0:8080");
