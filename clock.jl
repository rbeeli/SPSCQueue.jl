import Base.Libc.Libdl
# import LLVM

const librt = Libdl.find_library(["librt.so"])

# Identifier for system-wide realtime clock.
const CLOCK_REALTIME::Int32 = 0

# Monotonic system-wide clock.
const CLOCK_MONOTONIC::Int32 = 1


mutable struct Clock
    sec::Int64
    nsec::Int64
    Clock() = new(0, 0)
end

function clock_monotonic_ns(c::Clock)::Int64
    ptr = pointer_from_objref(c)
    ccall((:clock_gettime, librt), Int32, (Int32, Ptr{Clock}), CLOCK_MONOTONIC, ptr)
    c.sec * 1000000000 + c.nsec
end

# using StaticArrays
# function timestamp_ns()::Int64
#     # c = zeros(Int64, 2)
#     c = zero(MVector{2, Int64})
#     ptr = pointer_from_objref(c)
#     ccall((:clock_gettime, librt), Int32, (Int32, Ptr{Clock}), CLOCK_REALTIME, ptr)
#     return c[1] * 1000000000 + c[2]
# end

# function timestamp_ns(c::Clock)::Int64
#     ptr = pointer_from_objref(c)
#     ccall((:clock_gettime, librt), Int32, (Int32, Ptr{Clock}), CLOCK_REALTIME, ptr)
#     return c.sec * 1000000000 + c.nsec
# end

function timestamp_ns()::UInt64
    c::Clock = Clock()
    ptr = pointer_from_objref(c)
    ccall((:clock_gettime, librt), Int32, (Int32, Ptr{Clock}), CLOCK_REALTIME, ptr)
    c.sec * 1000000000 + c.nsec
end

# println(timestamp_ns())

# using BenchmarkTools
# display(@benchmark timestamp_ns())

# c::Clock = Clock()
# display(@benchmark timestamp_ns(c))

# display(@benchmark timestamp_ns2())


@inline function mm_pause()::Nothing
    # tail call void @llvm.x86.sse2.pause()
    Base.llvmcall("""
        call void asm sideeffect "pause", ""()
        ret void
        """, Cvoid, Tuple{})
    nothing
end

# function test()
#     start = rdtsc()
#     get_clock_monotonic_ns(Clock(0, 0))
#     end_ = rdtsc()
#     elapsed_cycles = end_ - start
#     elapsed_cycles
# end

# elapsed = 0.0
# n = 10_000
# for i in 1:n
#     global elapsed
#     elapsed += test()
# end
# println("Elapsed cycles: $(elapsed/n)")



# using InteractiveUtils
# display(@code_native debuginfo=:none rdtsc())


# using BenchmarkTools
# const c = Clock(0, 0)
# display(@benchmark get_clock_monotonic_ns(c))
