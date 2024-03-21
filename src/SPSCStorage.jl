"""
    SPSCStorage(buffer_size::Integer)
    SPSCStorage(ptr::Ptr{UInt8}, storage_size::Integer, owns_buffer::Bool)
    SPSCStorage(ptr::Ptr{UInt8}, owns_buffer::Bool, malloc_ptr::Ptr{UInt8})

Encapsulates the memory storage for SPSC queues.

NOTE: If `owns_buffer` is `true`, the memory will be freed
when the object is no longer referenced through a call to C's `free`.
This does not work for shared memory, thus shared memory must be freed manually.

The storage underlying the SPSC queues has the following
fixed, contiguous memory layout:

| Offset (bytes) | Length (bytes) | Description    |
|----------------|----------------|----------------|
| 0              | 8              | Storage size   |
| 8              | 56             | Pad            |
| 64             | 8              | Buffer size    |
| 72             | 56             | Pad            |
| 128            | 8              | Buffer offset  |
| 136            | 56             | Pad            |
| 192            | 8              | Read index     |
| 200            | 56             | Pad            |
| 256            | 8              | Write index    |
| 264            | 56             | Pad            |
| 320            | buffer_size    | Data buffer    |

Pad is used to align the buffer to 64 bytes (cache line size).

This memory layout enables us to use this data structure
inside shared memory, and potentially as IPC mechanism
to other languages, e.g. C++.

The struct is declared as immutable to ensure that the
finalizer is called by the GC when the object is no longer referenced.
"""
mutable struct SPSCStorage
    const storage_size::UInt64
    const buffer_size::UInt64
    const buffer_offset::UInt64
    const malloc_ptr::Ptr{UInt8}
    const storage_ptr::Ptr{UInt8}
    const buffer_ptr::Ptr{UInt8}
    const owns_buffer::Bool
    read_ix::Ptr{UInt64}
    write_ix::Ptr{UInt64}

    SPSCStorage(ptr::Ptr{UInt8}, owns_buffer::Bool, malloc_ptr::Ptr{UInt8}) = begin
        if malloc_ptr == C_NULL
            malloc_ptr = ptr
        end
        # read existing SPSCStorage from memory
        buffer_offset::UInt64 = unsafe_load(reinterpret(Ptr{UInt64}, ptr + 2 * 64))
        obj = new(
            unsafe_load(reinterpret(Ptr{UInt64}, ptr)), # storage size
            unsafe_load(reinterpret(Ptr{UInt64}, ptr + 1 * 64)), # buffer size
            unsafe_load(reinterpret(Ptr{UInt64}, ptr + 2 * 64)), # buffer offset
            malloc_ptr, # malloc_ptr
            ptr, # storage_ptr
            ptr + buffer_offset, # buffer_ptr
            owns_buffer,
            reinterpret(Ptr{UInt64}, ptr + 3 * 64), # read_ix (0-based)
            reinterpret(Ptr{UInt64}, ptr + 4 * 64), # write_ix (0-based)
        )
        # register finalizer to free memory
        finalizer(finalizer, obj)
        obj
    end

    SPSCStorage(ptr::Ptr{UInt8}, storage_size::Integer, owns_buffer::Bool) = begin
        # write storage metadata to memory region
        spsc_storage_set_metadata!(ptr, UInt64(storage_size), UInt64(0), UInt64(0))

        SPSCStorage(ptr, owns_buffer, ptr)
    end

    SPSCStorage(buffer_size::Integer) = begin
        buffer_offset::UInt64 = 320
        storage_size::UInt64 = UInt64(buffer_size) + buffer_offset

        # allocate heap memory for storage
        malloc_size = storage_size + 64
        malloc_ptr::Ptr{UInt8} = Base.Libc.malloc(malloc_size)

        # align ptr to 64 bytes
        ptr = reinterpret(Ptr{UInt8}, (reinterpret(UInt64, malloc_ptr) + 63) & ~UInt64(63))

        # write storage metadata to memory region
        spsc_storage_set_metadata!(ptr, storage_size, UInt64(0), UInt64(0))

        SPSCStorage(ptr, true, malloc_ptr)
    end
end

function spsc_storage_set_metadata!(storage_ptr::Ptr{UInt8}, storage_size::UInt64, read_ix::UInt64, write_ix::UInt64)::Nothing
    # write storage metadata to memory
    buffer_offset::UInt64 = 320
    buffer_size::UInt64 = storage_size - buffer_offset
    unsafe_store!(reinterpret(Ptr{UInt64}, storage_ptr), storage_size)
    unsafe_store!(reinterpret(Ptr{UInt64}, storage_ptr + 64), buffer_size)
    unsafe_store!(reinterpret(Ptr{UInt64}, storage_ptr + 64 * 2), buffer_offset) # buffer offset
    unsafe_store!(reinterpret(Ptr{UInt64}, storage_ptr + 64 * 3), read_ix, :release) # read_ix (0-based)
    unsafe_store!(reinterpret(Ptr{UInt64}, storage_ptr + 64 * 4), write_ix, :release) # write_ix (0-based)
    nothing
end

function Base.finalizer(storage::SPSCStorage)
    if storage.owns_buffer
        Base.Libc.free(storage.malloc_ptr)
    end
end
