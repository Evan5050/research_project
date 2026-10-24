using Test
using NextLab
using HTTP
using JSON
using CSV

include("data_tests.jl")
include("core_tests.jl")

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

        @testset "pendulum metadata over HTTP has provenance and no hidden period" begin
            resp = HTTP.get("$base/api/pendulum")
            @test resp.status == 200
            text = String(resp.body)
            body = JSON.parse(text)
            @test body["provenance"]["collected_by_nextlab_user"] == false
            @test body["provenance"]["x"]["unit"] == "m"
            @test body["state"]["observations"] == 9
            @test body["state"]["lengths_measured"] == 3
            hidden = Set(r.period_s for r in NextLab.load_pendulum() if r.length_m > 0.411)
            @test isempty(intersect(Set(numbers_in(text)), hidden))
            reset = HTTP.post("$base/api/pendulum/reset")
            @test JSON.parse(String(reset.body))["state"] == body["state"]
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
