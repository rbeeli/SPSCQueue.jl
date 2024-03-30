const SPSC_STORAGE_CACHE_LINE_SIZE::UInt64 = 64
const SPSC_STORAGE_BUFFER_OFFSET::UInt64 = 3 * 64

"""
    SPSCStorage(storage_size::Integer)
    SPSCStorage(ptr::Ptr{T}, storage_size::Integer; finalizer_fn::Function)
    SPSCStorage(ptr::Ptr{T}; finalizer_fn::Function)

Encapsulates the memory storage for SPSC queues.

The storage underlying the SPSC queues has the following
fixed, contiguous memory layout:

| Offset (bytes) | Length (bytes) | Description    |
|----------------|----------------|----------------|
| 0              | 8              | Storage size   |
| 8              | 56             | Pad            |
| 64             | 8              | Read index     |
| 72             | 56             | Pad            |
| 128            | 8              | Write index    |
| 136            | 56             | Pad            |
| 192            | buffer_size    | Data buffer    |

Pad is used to align the buffer to 64 bytes (cache line size).

This memory layout ensure cache line alignment for the read and write indices,
and can be used inside shared memory, e.g. as IPC mechanism to other languages (processes).

The struct is declared as mutable to ensure that the
finalizer is called by the GC when the object is no longer referenced.
An optional `finalizer_fn` function can be provided to perform additional cleanup
when the object is finalized by the GC, e.g. `free`ing  `malloc`ed memory.
"""
mutable struct SPSCStorage
    const storage_size::UInt64
    const buffer_size::UInt64
    const storage_ptr::Ptr{UInt8}
    const buffer_ptr::Ptr{UInt8}
    const finalizer_fn::Function
    read_ix::Ptr{UInt64}
    write_ix::Ptr{UInt64}

    """
    Reads the SPSC storage data from an existing initialized memory region.
    """
    SPSCStorage(ptr::Ptr{T}; finalizer_fn::Function=s -> nothing) where T = begin
        ptr8::Ptr{UInt8} = reinterpret(Ptr{UInt8}, ptr)
        storage_size::UInt64 = unsafe_load(reinterpret(Ptr{UInt64}, ptr8))
        buffer_size::UInt64 = storage_size - SPSC_STORAGE_BUFFER_OFFSET

        obj = new(
            storage_size, # storage size
            buffer_size, # buffer size
            ptr8, # storage_ptr
            ptr8 + SPSC_STORAGE_BUFFER_OFFSET, # buffer_ptr
            finalizer_fn,
            reinterpret(Ptr{UInt64}, ptr8 + SPSC_STORAGE_CACHE_LINE_SIZE), # read_ix (0-based)
            reinterpret(Ptr{UInt64}, ptr8 + SPSC_STORAGE_CACHE_LINE_SIZE * 2), # write_ix (0-based)
        )
        # register finalizer to free memory on GC collection
        finalizer(finalizer, obj)
        obj
    end

    """
    Initializes new SPSC storage with the given memory region.

    Note that `storage_size` is the total size of the memory region,
    not just `buffer_size`. `storage_size = SPSC_STORAGE_BUFFER_OFFSET + buffer_size`.
    """
    SPSCStorage(ptr::Ptr{T}, storage_size::Integer; finalizer_fn::Function=s -> nothing) where T = begin
        ptr8::Ptr{UInt8} = reinterpret(Ptr{UInt8}, ptr)

        # write storage metadata to memory region
        spsc_storage_set_metadata!(ptr8, UInt64(storage_size), UInt64(0), UInt64(0))

        SPSCStorage(ptr8; finalizer_fn=finalizer_fn)
    end

    """
    Initializes new SPSC storage with given buffer size.

    Note that `buffer_size` is the size of the memory region used by the SPSC queue.
    The effective memory region size including metadata is `buffer_size + SPSC_STORAGE_BUFFER_OFFSET`.
    """
    SPSCStorage(storage_size::Integer) = begin
        # allocate heap memory for storage (aligned to cache line size)
        ptr::Ptr{UInt8} = SPSCMemory.aligned_alloc(storage_size, SPSC_STORAGE_CACHE_LINE_SIZE)

        # write storage metadata to memory region
        spsc_storage_set_metadata!(ptr, UInt64(storage_size), UInt64(0), UInt64(0))

        function finalizer(storage::SPSCStorage)
            SPSCMemory.aligned_free(storage.storage_ptr)
        end

        SPSCStorage(ptr; finalizer_fn=finalizer)
    end
end

function spsc_storage_set_metadata!(storage_ptr::Ptr{UInt8}, storage_size::UInt64, read_ix::UInt64, write_ix::UInt64)::Nothing
    # write storage metadata to memory
    unsafe_store!(reinterpret(Ptr{UInt64}, storage_ptr), storage_size)
    unsafe_store!(reinterpret(Ptr{UInt64}, storage_ptr + SPSC_STORAGE_CACHE_LINE_SIZE), read_ix, :release) # read_ix (0-based)
    unsafe_store!(reinterpret(Ptr{UInt64}, storage_ptr + SPSC_STORAGE_CACHE_LINE_SIZE * 2), write_ix, :release) # write_ix (0-based)
    nothing
end

function Base.finalizer(storage::SPSCStorage)
    storage.finalizer_fn(storage)
end
