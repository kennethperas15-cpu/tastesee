import asyncio
from datetime import datetime
from pyscript import document, window
import js

class MessagingSystem:
    def __init__(self):
        self.conversations = [
            {
                "id": "conv-1",
                "partner_name": "John Reyes",
                "partner_role": "Assigned Delivery Rider",
                "avatar": "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&q=80&w=150",
                "order_no": "TSB-2026-001",
                "product": "Box of 6 Classic Cinnamon Buns",
                "status": "Out for Delivery",
                "unread": 1,
                "last_message": "I am on my way with your cinnamon buns!",
                "last_time": "10:42 AM"
            }
        ]
        
        self.messages = {
            "conv-1": [
                {
                    "sender": "John Reyes",
                    "role": "rider",
                    "text": "Hello Maria! I have picked up your box of Classic Cinnamon Buns from the bakery and I am heading your way now.",
                    "time": "10:30 AM",
                    "status": "read"
                },
                {
                    "sender": "Maria Santos",
                    "role": "customer",
                    "text": "Awesome, thank you John! Please buzz unit 4B upon arrival.",
                    "time": "10:32 AM",
                    "status": "read"
                },
                {
                    "sender": "John Reyes",
                    "role": "rider",
                    "text": "I am on my way with your cinnamon buns! ETA is approximately 12 minutes.",
                    "time": "10:42 AM",
                    "status": "read"
                }
            ]
        }
        self.active_conv_id = "conv-1"

    def show_toast(self, title, message, toast_type="success"):
        try:
            container = document.getElementById("toast-container")
            if not container:
                return
            
            toast_el = document.createElement("div")
            toast_el.className = f"toast {toast_type}"
            
            icon_class = "fa-circle-check" if toast_type == "success" else "fa-circle-exclamation"
            if toast_type == "info":
                icon_class = "fa-bell"
                
            toast_el.innerHTML = f"""
                <i class="fa-solid {icon_class}"></i>
                <div class="toast-content">
                    <h5>{title}</h5>
                    <p>{message}</p>
                </div>
            """
            container.appendChild(toast_el)
            
            def remove_toast(*args):
                try:
                    toast_el.remove()
                except:
                    pass
            window.setTimeout(js.eval("(fn) => { return () => { fn(); }")(remove_toast), 4000)
        except Exception as e:
            print("Toast error:", e)

    def send_message(self, text):
        if not text or not text.strip():
            return
        
        clean_text = text.strip()
        current_time = datetime.now().strftime("%I:%M %p")
        
        new_msg = {
            "sender": "Maria Santos",
            "role": "customer",
            "text": clean_text,
            "time": current_time,
            "status": "delivered"
        }
        
        if self.active_conv_id not in self.messages:
            self.messages[self.active_conv_id] = []
            
        self.messages[self.active_conv_id].append(new_msg)
        
        for conv in self.conversations:
            if conv["id"] == self.active_conv_id:
                conv["last_message"] = clean_text
                conv["last_time"] = current_time

        self.render_active_chat()
        self.render_conversations()
        
        async def simulate_rider_reply():
            typing_el = document.getElementById("typing-indicator")
            if typing_el:
                typing_el.classList.remove("hidden")
            
            await asyncio.sleep(2.5)
            
            if typing_el:
                typing_el.classList.add("hidden")
                
            reply_text = "Got it! I am just around the corner and will be at your gate shortly."
            reply_time = datetime.now().strftime("%I:%M %p")
            
            self.messages[self.active_conv_id].append({
                "sender": "John Reyes",
                "role": "rider",
                "text": reply_text,
                "time": reply_time,
                "status": "delivered"
            })
            
            for conv in self.conversations:
                if conv["id"] == self.active_conv_id:
                    conv["last_message"] = reply_text
                    conv["last_time"] = reply_time
                    conv["unread"] = 1
            
            self.render_active_chat()
            self.render_conversations()
            self.show_toast("New Message from John", "I am just around the corner...", "info")

        asyncio.ensure_future(simulate_rider_reply())

    def render_active_chat(self):
        container = document.getElementById("messages-container")
        if not container:
            return
            
        msgs = self.messages.get(self.active_conv_id, [])
        html_content = '<div class="date-separator"><span>Today, October 21</span></div>'
        
        for msg in msgs:
            is_incoming = msg["role"] == "rider"
            item_class = "incoming" if is_incoming else "outgoing"
            
            avatar_html = '<img src="https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&q=80&w=100" class="msg-avatar" alt="John">' if is_incoming else ''
            
            status_icon = '<i class="fa-solid fa-check-double read"></i>' if msg["status"] == "read" else '<i class="fa-solid fa-check"></i>'
            
            html_content += f"""
                <div class="message-item {item_class}">
                    {avatar_html}
                    <div class="msg-content-wrap">
                        <div class="msg-bubble">{msg['text']}</div>
                        <div class="msg-meta">
                            <span class="msg-time">{msg['time']}</span>
                            {'<span class="msg-status">' + status_icon + '</span>' if not is_incoming else ''}
                        </div>
                    </div>
                </div>
            """
        
        container.innerHTML = html_content
        container.scrollTop = container.scrollHeight

    def render_conversations(self):
        list_container = document.getElementById("conversation-list")
        if not list_container:
            return
            
        html_content = ""
        for conv in self.conversations:
            is_active = "active" if conv["id"] == self.active_conv_id else ""
            unread_badge = f'<span class="unread-badge">{conv["unread"]}</span>' if conv["unread"] > 0 else ''
            
            html_content += f"""
                <div class="conversation-item {is_active}" data-id="{conv['id']}">
                    <div class="avatar-wrapper">
                        <img src="{conv['avatar']}" alt="{conv['partner_name']}" class="conv-avatar">
                        <span class="status-dot online"></span>
                    </div>
                    <div class="conv-details">
                        <div class="conv-header-row">
                            <h4>{conv['partner_name']}</h4>
                            <span class="conv-time">{conv['last_time']}</span>
                        </div>
                        <p class="conv-preview">{conv['last_message']}</p>
                        <div class="conv-meta-row">
                            <span class="order-tag">{conv['order_no']}</span>
                            {unread_badge}
                        </div>
                    </div>
                </div>
            """
        list_container.innerHTML = html_content

app = MessagingSystem()

def setup_event_listeners():
    send_btn = document.getElementById("send-btn")
    message_input = document.getElementById("message-input")
    
    def on_send(event):
        if message_input and message_input.value:
            val = message_input.value
            message_input.value = ""
            message_input.style.height = "auto"
            document.getElementById("char-counter").textContent = "0/500"
            document.getElementById("send-btn").setAttribute("disabled", "true")
            app.send_message(val)

    if send_btn:
        send_btn.onclick = on_send
        
    if message_input:
        def on_keypress(e):
            if e.key == "Enter" and not e.shiftKey:
                e.preventDefault()
                if message_input.value.strip():
                    val = message_input.value
                    message_input.value = ""
                    message_input.style.height = "auto"
                    document.getElementById("char-counter").textContent = "0/500"
                    document.getElementById("send-btn").setAttribute("disabled", "true")
                    app.send_message(val)
        message_input.onkeydown = on_keypress

app.render_conversations()
app.render_active_chat()
setup_event_listeners()
