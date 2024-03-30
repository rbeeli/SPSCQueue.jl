module SPSCMemory

mutable struct AlignedAllocStats
    count::Int64
end

const _ALIGNED_ALLOC_STATS = AlignedAllocStats(0)

"""
Allocates memory with a given alignment.
The returned memory must be freed using `aligned_free` manually.
"""
function aligned_alloc(size::Integer, align::Integer)
    pt = ccall(:aligned_alloc, Ptr{Cvoid}, (Base.Csize_t, Base.Csize_t), Base.Csize_t(align), Base.Csize_t(size))
    @assert pt != C_NULL "failed to allocate aligned memory"
    _ALIGNED_ALLOC_STATS.count += 1
    # return unsafe_wrap(Array, convert(Ptr{T}, pt), dims; own=true)
    pt
end

"""
Frees memory allocated by `aligned_alloc`.
"""
function aligned_free(ptr::Ptr{T}) where {T}
    ccall(:free, Cvoid, (Ptr{Cvoid},), ptr)
    _ALIGNED_ALLOC_STATS.count -= 1
end

"""
Returns the number of aligned memory allocations not yet freed.
"""
function aligned_alloc_count()
    _ALIGNED_ALLOC_STATS.count
end

export aligned_alloc, aligned_free, aligned_alloc_count

end # module
