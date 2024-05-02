"""
A Single-Producer Single-Consumer (SPSC) queue with variable-sized message buffer.
"""
mutable struct SPSCQueueVar
    cached_read_ix::UInt64
    __0::NTuple{7,UInt64}
    cached_write_ix::UInt64
    __1::NTuple{7,UInt64}
    const storage::SPSCStorage
    const max_message_size::UInt64

    SPSCQueueVar(storage::SPSCStorage) = new(
        unsafe_load(storage.read_ix, :acquire),
        ntuple(identity, 7), # padding
        unsafe_load(storage.write_ix, :acquire),
        ntuple(identity, 7), # padding
        storage,
        storage.buffer_size / 2,
    )
end

"""
Enqueues a message in the queue. Returns `true` if successful, `false` if the queue is full.
"""
@inline function enqueue!(queue::SPSCQueueVar, val::SPSCMessage)::Bool
    write_ix::UInt64 = unsafe_load(queue.storage.write_ix, :monotonic)
    msg_total_size::UInt64 = total_size(val)
    next_write_ix::UInt64 = next_index(write_ix, msg_total_size)

    if next_write_ix < queue.storage.buffer_size # 0-based indexing
        # not crossing the buffer boundary

        # check if we would cross the reader (>= because == means queue is empty)
        if write_ix < queue.cached_read_ix && next_write_ix ≥ queue.cached_read_ix
            queue.cached_read_ix = unsafe_load(queue.storage.read_ix, :acquire)
            if write_ix < queue.cached_read_ix && next_write_ix ≥ queue.cached_read_ix
                return false  # queue full
            end
        end
    else
        # crossing the end -> wrap around

        # check if we would cross the reader
        next_write_ix = next_index(UInt64(0), msg_total_size) # 0-based indexing
        if next_write_ix ≥ queue.cached_read_ix
            queue.cached_read_ix = unsafe_load(queue.storage.read_ix, :acquire)
            if next_write_ix ≥ queue.cached_read_ix
                return false  # queue full
            end
        end

        # write 0 size at current write_ix to indicate wrap around
        unsafe_store!(reinterpret(Ptr{UInt64}, queue.storage.buffer_ptr + write_ix), UInt64(0))

        write_ix = UInt64(0)
    end

    # write to buffer
    unsafe_store!(reinterpret(Ptr{UInt64}, queue.storage.buffer_ptr + write_ix), payload_size(val))
    unsafe_copyto!(queue.storage.buffer_ptr + write_ix + sizeof(UInt64), val.data, payload_size(val))

    # update write index
    unsafe_store!(queue.storage.write_ix, next_write_ix, :release)

    true # success
end

"""
Reads the next message from the queue.
Returns a message view with `size = 0` if the queue is empty (`SPSC_MESSAGE_VIEW_EMPTY`).
Call `isempty(msg)` to check if a message was dequeued successfully.

The reader only advances after calling `dequeue_commit!`, this allows to use the
message view without copying the data to another buffer between `dequeue_begin!` and `dequeue_commit!`.

Failing to call `dequeue_commit!` is allowed, but means the reader will not advance.
"""
@inline function dequeue_begin!(queue::SPSCQueueVar)::SPSCMessageView
    @label recheck_read_index
    read_ix::UInt64 = unsafe_load(queue.storage.read_ix, :monotonic)

    # check if queue is empty
    if read_ix == queue.cached_write_ix
        queue.cached_write_ix = unsafe_load(queue.storage.write_ix, :acquire)
        if read_ix == queue.cached_write_ix
            return SPSC_MESSAGE_VIEW_EMPTY  # queue is empty
        end
    end

    # read message size
    message_size::UInt64 = unsafe_load(reinterpret(Ptr{UInt64}, queue.storage.buffer_ptr + read_ix))
    if message_size == 0
        # message wraps around, move to beginning of queue
        unsafe_store!(queue.storage.read_ix, UInt64(0), :release) # 0-based indexing
        # recheck read index
        @goto recheck_read_index
    end

    # read message
    data::Ptr{UInt8} = reinterpret(Ptr{UInt8}, queue.storage.buffer_ptr + read_ix + 8)
    msg = SPSCMessageView(message_size, data, read_ix)

    msg
end

"""
Moves the reader index to the next message in the queue.
Call this after processing a message returned by `dequeue_begin!`.
The message view is no longer valid after this call.
"""
@inline function dequeue_commit!(queue::SPSCQueueVar, msg::SPSCMessageView)::Nothing
    next_read_ix = next_index(msg.index, msg.size + 8)
    unsafe_store!(queue.storage.read_ix, next_read_ix, :release)
    nothing
end

@inline function next_index(current_index::UInt64, size::UInt64)::UInt64
    # ensure it's 8-byte aligned
    (current_index + size + 7) & ~UInt64(7)
end

"""
Returns `true` if the SPSC queue is empty.
Does not dequeue any messages (read-only operation).

There is no guarantee that the queue is still empty after this function returns,
as the writer might have enqueued a message immediately after the check.
"""
@inline function Base.isempty(queue::SPSCQueueVar)::Bool
    unsafe_load(queue.storage.read_ix, :acquire) == unsafe_load(queue.storage.write_ix, :acquire)
end

"""
Returns `false` if the SPSC queue is empty.
Does not dequeue any messages (read-only operation).

To be used by consumer thread only due to memory order optimization.
"""
@inline function can_dequeue(queue::SPSCQueueVar)::Bool
    unsafe_load(queue.storage.read_ix, :monotonic) ≠ unsafe_load(queue.storage.write_ix, :acquire)
end
