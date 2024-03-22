"""

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
Enqueues a message in the queue.
Returns `false` if the queue is full.
If successfully enqueued, returns `true`.
"""
@inline function enqueue(queue::SPSCQueueVar, val::SPSCMessage)::Bool
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
Returns MESSAGE_VIEW_EMPTY if the queue is empty, which has `size` of 0.
Call `isempty` to check if a message was dequeued successfully.

Note: You MUST call `dequeue_commit!` after processing the message to move the reader index.
"""
@inline function dequeue(queue::SPSCQueueVar)::SPSCMessageView
    @label recheck_read_index
    read_ix::UInt64 = unsafe_load(queue.storage.read_ix, :monotonic)

    # check if queue is empty
    if read_ix == queue.cached_write_ix
        queue.cached_write_ix = unsafe_load(queue.storage.write_ix, :acquire)
        if read_ix == queue.cached_write_ix
            return MESSAGE_VIEW_EMPTY  # queue is empty
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
Moves the reader index to the next message.
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
