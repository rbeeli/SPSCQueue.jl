using Base.Filesystem
using Base.Libc: strerror
using Base: unsafe_convert

const PROT_READ  = 0x01
const PROT_WRITE = 0x02
const MAP_SHARED = 0x01

const __off64_t = Clong
const __mode_t = UInt32


"""
Opens or creates a shared memory object. Calls `ftruncate` to set the size
of the shared memory region. Furthermore, calls `mmap` to map the shared
memory region into the address space of the calling process.

# Returns
- `fd::File` - file descriptor
- `size` - size of shared memory region
- `ptr::Ptr{UInt8}` - pointer to shared memory region

# References
https://pubs.opengroup.org/onlinepubs/007904875/functions/shm_open.html
"""
function shm_open(
    shm_name::String
    ;
    shm_flags=Base.Filesystem.JL_O_RDWR,
    shm_mode=0o666,
    size=-1
)::Tuple{File, Int, Ptr{UInt8}}
    # file descriptor
    fd_handle = @ccall shm_open(shm_name::Cstring, shm_flags::Cint, shm_mode::__mode_t)::Cint
    if fd_handle == -1
        error("Shared memory '$shm_name' shm_open failed: $(strerror())")
    end

    fd = File(RawFD(fd_handle))

    if shm_flags & JL_O_CREAT != 0
        if size <= 0
            error("Shared memory '$shm_name' size must be specified when creating with JL_O_CREAT flag.")
        end

        # set size of shared memory region
        rc = @ccall ftruncate(fd.handle::Cint, size::Csize_t)::Int
        if rc == -1
            close(fd)
            error("Shared memory '$shm_name' shm_open ftruncate failed: $(strerror())")
        end
    else
        # read size of existing shared memory region
        try
            s = stat(fd)
            size = s.size
        catch e
            close(fd)
            error("Shared memory '$shm_name' shm_open stat failed. Error: $e")
        end
    end


    # map shared memory region
    prot::Cint = PROT_READ | PROT_WRITE
    flags::Cint = MAP_SHARED
    c_ptr = @ccall mmap(C_NULL::Ptr{Cvoid}, size::Csize_t, prot::Cint, flags::Cint, fd.handle::Cint, 0::__off64_t)::Ptr{Cvoid}
    if reinterpret(Int, c_ptr) == -1
        close(fd)
        error("Shared memory '$shm_name' shm_open mmap failed: $(strerror())")
    end

    ptr = reinterpret(Ptr{UInt8}, c_ptr)

    fd, size, ptr
end

function unlink_shm(shm_name)
    res::Int = ccall(:shm_unlink, Int, (Ptr{UInt8}, ), shm_name)
    if res == -1
        error("shm_unlink() failed")
    end
end
