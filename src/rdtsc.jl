using ThreadPinning

@inline function rdtsc()::UInt64
    # https://github.com/m-j-w/CpuId.jl/blob/fd39b7b89755b9d7e69354f22fb81559f93d2e3a/src/CpuInstructions.jl#L80
    Base.llvmcall(
        """
        %1 = tail call { i32, i32 } asm sideeffect "rdtsc", "={ax},={dx},~{dirflag},~{fpsr},~{flags}"() #2
        %2 = extractvalue { i32, i32 } %1, 0
        %3 = extractvalue { i32, i32 } %1, 1
        %4 = zext i32 %2 to i64
        %5 = zext i32 %3 to i64
        %6 = shl nuw i64 %5, 32
        %7 = or i64 %6, %4
        ret i64 %7
        """, UInt64, Tuple{})
end

"""
Measures the number of cycles per nanosecond using the rdtsc instruction.
This measure is highly CPU/core specific and depends on power settings of
the machine. Use with caution. Usually only neede for very low-latency /
high throughput applications measuring with nanosecond precision.

Otherwise, consider using `get_clock_monotonic_ns` which is more portable
and reliable, or Julia's `time_ns`.

Example
-------

    t = @tspawnat 1 rdtsc_cycles_per_ns()
    cycles_per_ns = fetch(t)
    println("cycles per ns: \$cycles_per_ns")
"""
function rdtsc_cycles_per_ns(; wait_s=0.05, trials=5, cpu_affinity::Int=1)::Float64
    setaffinity([cpu_affinity])

    best_cycles_per_ns = 0.0
    for _ in 1:trials
        c0 = rdtsc()
        t = time_ns()
        while true
            # busy wait
            time_ns() - t > 1e9 * wait_s && break
        end
        c1 = rdtsc()
        cycles_per_ns = (c1 - c0) / 1e9 / wait_s
        if cycles_per_ns > best_cycles_per_ns
            best_cycles_per_ns = cycles_per_ns
        end
    end

    best_cycles_per_ns
end
