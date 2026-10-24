using Test
using NextLab
using HTTP
using JSON

@testset "NextLab API" begin
    server = NextLab.start_server(; port = 0)
    base = "http://127.0.0.1:$(HTTP.port(server))"
    try
        @testset "health responds with real backend facts" begin
            resp = HTTP.get("$base/api/health")
            @test resp.status == 200
            @test occursin("application/json", HTTP.header(resp, "Content-Type"))
            body = JSON.parse(String(resp.body))
            @test body["status"] == "ok"
            @test body["service"] == "nextlab-backend"
            @test body["julia_version"] == string(VERSION)
        end

        @testset "unknown API route is a JSON 404, not a fake success" begin
            resp = HTTP.get("$base/api/does-not-exist"; status_exception = false)
            @test resp.status == 404
            @test JSON.parse(String(resp.body))["error"] == "not found"
        end
    finally
        close(server)
    end
end
