struct SPSCMessage
    size::UInt64
    data::Ptr{UInt8}
    SPSCMessage(data::Ptr{T}, size::TSize) where {T, TSize <: Integer} = new(UInt64(size), reinterpret(Ptr{UInt8}, data))
end
@inline total_size(msg::SPSCMessage)::UInt64 = sizeof(UInt64) + msg.size
@inline payload_size(msg::SPSCMessage)::UInt64 = msg.size


"""
    SPSCMessageView

A lightweight view into a message in the SPSC queue.

The underlying memory can be accessed and modified through the `data` field
until `dequeue_commit!` is called.

The `size` field contains the size of the message in bytes.

The `index` field contains the 0-based index of the message in the queue's buffer.
"""
struct SPSCMessageView
    size::UInt64
    data::Ptr{UInt8}
    index::UInt64
end
const MESSAGE_VIEW_EMPTY::SPSCMessageView = SPSCMessageView(0, C_NULL, 0);

@inline Base.isempty(view::SPSCMessageView)::Bool = view.size == 0
