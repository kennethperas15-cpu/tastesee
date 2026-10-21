// --- Mock Data Store ---
let currentRole = 'customer'; // 'customer' or 'rider'
let soundEnabled = true;

const timelineSteps = ['Order Confirmed', 'Preparing', 'Out for Delivery', 'Arrived', 'Delivered'];

let conversationsData = [
    {
        id: 'conv-1',
        customerName: 'Maria Santos',
        customerAvatar: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150',
        riderName: 'Kuya Juan',
        riderAvatar: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
        orderNo: 'TS-8492',
        status: 'Out for Delivery',
        estArrival: '12:45 PM',
        address: 'Blk 4 Lot 12, Sunnyville Subd, Cebu City',
        unreadCount: 0,
        online: true,
        items: [
            { name: 'Box of 6 Classic Cinnamon Buns', qty: 1, price: '₱450.00' },
            { name: 'Extra Cream Cheese Frosting', qty: 2, price: '₱100.00' }
        ],
        messages: [
            { sender: 'customer', text: 'Hi Kuya Juan! Please make sure the box is handled carefully, they are warm cinnamon buns! 🧁', time: '12:15 PM' },
            { sender: 'rider', text: "Hello Ma'am Maria! Yes po, secured sa box and kept warm. On my way na po sa Sunnyville!", time: '12:18 PM' },
            { sender: 'rider', text: "I'm about 5 minutes away from your location.", time: '12:35 PM' }
        ]
    },
    {
        id: 'conv-2',
        customerName: 'Carlo Mendoza',
        customerAvatar: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150',
        riderName: 'Kuya Juan',
        riderAvatar: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
        orderNo: 'TS-8495',
        status: 'Preparing',
        estArrival: '1:15 PM',
        address: 'Tower 2, IT Park, Lahug, Cebu City',
        unreadCount: 2,
        online: false,
        items: [
            { name: 'Box of 4 Pecan Caramel Buns', qty: 1, price: '₱380.00' },
            { name: 'Iced Latte (Large)', qty: 1, price: '₱140.00' }
        ],
        messages: [
            { sender: 'customer', text: 'Hello, please leave the order at the lobby reception desk if I am in a meeting.', time: '12:50 PM' },
            { sender: 'rider', text: 'Noted sir Carlo! Will update you once delivered.', time: '12:52 PM' }
        ]
    },
    {
        id: 'conv-3',
        customerName: 'Atty. Sarah Jenkins',
        customerAvatar: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
        riderName: 'Kuya Juan',
        riderAvatar: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
        orderNo: 'TS-8501',
        status: 'Order Confirmed',
        estArrival: '2:00 PM',
        address: 'Escario St, Mango Avenue, Cebu City',
        unreadCount: 0,
        online: true,
        items: [
            { name: 'Box of 12 Assorted Buns', qty: 1, price: '₱850.00' }
        ],
        messages: [
            { sender: 'customer', text: 'Hi! Can you add a greeting note: "Happy Birthday Mom!"?', time: '1:00 PM' }
        ]
    }
];

let activeConversationId = 'conv-1';

// --- Web Audio API Chime Synthesis for Notifications ---
function playNotificationSound() {
    if (!soundEnabled) return;
    try {
        const AudioContext = window.AudioContext || window.webkitAudioContext;
        if (!AudioContext) return;
        const ctx = new AudioContext();
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        
        osc.type = 'sine';
        osc.frequency.setValueAtTime(587.33, ctx.currentTime); // D5
        osc.frequency.exponentialRampToValueAtTime(880, ctx.currentTime + 0.15); // A5

        gain.gain.setValueAtTime(0.15, ctx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.4);

        osc.connect(gain);
        gain.connect(ctx.destination);

        osc.start();
        osc.stop(ctx.currentTime + 0.4);
    } catch (e) {
        console.log('Audio Context suppressed or not allowed.', e);
    }
}

// --- Toast Notification System ---
function showToast(title, message, type = 'info') {
    const container = document.getElementById('toast-container');
    const toast = document.createElement('div');
    
    let bgClass = 'bg-white border-primary/40 text-darkBlue';
    let iconClass = 'fa-circle-info text-primary';
    if (type === 'success') {
        bgClass = 'bg-white border-green-300 text-darkBlue';
        iconClass = 'fa-circle-check text-green-500';
    }

    toast.className = `pointer-events-auto flex items-start gap-3 p-4 rounded-2xl shadow-xl border ${bgClass} w-80 animate-fade-in transition-all duration-300`;
    toast.innerHTML = `
        <div class="mt-0.5 text-lg"><i class="fa-solid ${iconClass}"></i></div>
        <div class="flex-1">
            <h5 class="font-bold text-xs leading-tight">${title}</h5>
            <p class="text-[11px] text-gray-500 mt-0.5">${message}</p>
        </div>
        <button onclick="this.parentElement.remove()" class="text-gray-400 hover:text-gray-600 text-xs cursor-pointer"><i class="fa-solid fa-xmark"></i></button>
    `;
    container.appendChild(toast);
    setTimeout(() => {
        toast.style.opacity = '0';
        setTimeout(() => toast.remove(), 300);
    }, 4000);
}

// --- Initialization on Load ---
window.onload = function() {
    renderApp();
    setupEventListeners();
};

function setupEventListeners() {
    // Search filter
    document.getElementById('conversation-search').addEventListener('input', (e) => {
        renderConversationsList(e.target.value);
    });

    // Mobile menu toggles
    document.getElementById('mobile-menu-btn').addEventListener('click', () => {
        document.getElementById('sidebar').classList.toggle('-translate-x-full');
    });
    document.getElementById('close-sidebar-btn').addEventListener('click', () => {
        document.getElementById('sidebar').classList.add('-translate-x-full');
    });
    document.getElementById('toggle-order-panel').addEventListener('click', () => {
        document.getElementById('order-panel').classList.toggle('translate-x-full');
        document.getElementById('order-panel').classList.toggle('hidden');
    });

    // Sound Toggle
    document.getElementById('sound-toggle-btn').addEventListener('click', () => {
        soundEnabled = !soundEnabled;
        const icon = document.getElementById('sound-icon');
        const text = document.getElementById('sound-text');
        if (soundEnabled) {
            icon.className = 'fa-solid fa-volume-high';
            text.textContent = 'Sound On';
            showToast('Sound Enabled', 'Notification chimes are active.', 'success');
        } else {
            icon.className = 'fa-solid fa-volume-xmark';
            text.textContent = 'Sound Off';
            showToast('Sound Muted', 'Notification chimes are disabled.', 'info');
        }
    });
}

// --- Role Switcher ---
function switchRole(role) {
    currentRole = role;
    const custBtn = document.getElementById('role-customer-btn');
    const riderBtn = document.getElementById('role-rider-btn');
    const riderControls = document.getElementById('rider-status-controls');
    const userAvatar = document.getElementById('current-user-avatar');
    const userName = document.getElementById('current-user-name');
    const userRoleLabel = document.getElementById('current-user-role-label');

    if (role === 'customer') {
        custBtn.className = 'px-3 py-1.5 text-xs font-semibold rounded-md transition-all duration-200 bg-white text-darkBlue shadow-sm cursor-pointer';
        riderBtn.className = 'px-3 py-1.5 text-xs font-semibold rounded-md text-gray-600 hover:text-darkBlue transition-all duration-200 cursor-pointer';
        riderControls.classList.add('hidden');
        userAvatar.src = 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150';
        userName.textContent = 'Maria Santos';
        userRoleLabel.textContent = 'Customer • Order #TS-8492';
        showToast('Switched to Customer View', 'You are now messaging as customer Maria Santos.', 'success');
    } else {
        riderBtn.className = 'px-3 py-1.5 text-xs font-semibold rounded-md transition-all duration-200 bg-white text-darkBlue shadow-sm cursor-pointer';
        custBtn.className = 'px-3 py-1.5 text-xs font-semibold rounded-md text-gray-600 hover:text-darkBlue transition-all duration-200 cursor-pointer';
        riderControls.classList.remove('hidden');
        userAvatar.src = 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150';
        userName.textContent = 'Kuya Juan';
        userRoleLabel.textContent = 'Delivery Rider • 3 Active Jobs';
        showToast('Switched to Delivery Rider View', 'You are now messaging as delivery rider Kuya Juan.', 'success');
    }
    renderApp();
}

// --- Main Render Function ---
function renderApp() {
    renderConversationsList();
    renderActiveChat();
    renderOrderPanel();
    renderQuickReplies();
}

// --- Render Conversations Sidebar List ---
function renderConversationsList(filter = '') {
    const listEl = document.getElementById('conversations-list');
    listEl.innerHTML = '';

    const filtered = conversationsData.filter(c => 
        c.customerName.toLowerCase().includes(filter.toLowerCase()) ||
        c.orderNo.toLowerCase().includes(filter.toLowerCase()) ||
        c.address.toLowerCase().includes(filter.toLowerCase())
    );

    if (filtered.length === 0) {
        listEl.innerHTML = `
            <div class="p-8 text-center text-gray-400">
                <i class="fa-solid fa-mug-hot text-3xl mb-2 text-primary/50"></i>
                <p class="text-xs font-medium">No conversations found</p>
            </div>
        `;
        return;
    }

    filtered.forEach(conv => {
        const isActive = conv.id === activeConversationId;
        const lastMsg = conv.messages[conv.messages.length - 1] || { text: 'No messages yet', time: '' };
        
        let displayAvatar = currentRole === 'customer' ? conv.riderAvatar : conv.customerAvatar;
        let displayName = currentRole === 'customer' ? `Rider: ${conv.riderName}` : conv.customerName;

        const item = document.createElement('div');
        item.className = `p-3.5 flex items-start gap-3 cursor-pointer transition border-b border-gray-100 ${isActive ? 'bg-paleBlue/80 border-l-4 border-l-darkBlue' : 'hover:bg-gray-50'}`;
        item.onclick = () => selectConversation(conv.id);

        item.innerHTML = `
            <div class="relative flex-shrink-0">
                <img src="${displayAvatar}" alt="Avatar" class="w-11 h-11 rounded-full object-cover border border-gray-200">
                ${conv.online ? '<span class="absolute bottom-0 right-0 w-3 h-3 bg-green-500 border-2 border-white rounded-full"></span>' : ''}
            </div>
            <div class="flex-1 min-w-0">
                <div class="flex items-center justify-between mb-0.5">
                    <h4 class="text-xs font-bold text-darkBlue truncate">${displayName}</h4>
                    <span class="text-[10px] text-gray-400 flex-shrink-0">${lastMsg.time}</span>
                </div>
                <p class="text-[11px] text-gray-500 truncate mb-1">Order #${conv.orderNo} • <span class="text-primary font-semibold">${conv.status}</span></p>
                <p class="text-xs text-gray-600 truncate">${lastMsg.text}</p>
            </div>
            ${conv.unreadCount > 0 ? `<div class="flex-shrink-0 bg-darkBlue text-white text-[10px] font-bold w-5 h-5 rounded-full flex items-center justify-center">${conv.unreadCount}</div>` : ''}
        `;
        listEl.appendChild(item);
    });
}

function selectConversation(id) {
    activeConversationId = id;
    const conv = conversationsData.find(c => c.id === id);
    if (conv) {
        conv.unreadCount = 0;
    }
    renderApp();
    if (window.innerWidth < 768) {
        document.getElementById('sidebar').classList.add('-translate-x-full');
    }
}

// --- Render Active Chat Area ---
function renderActiveChat() {
    const conv = conversationsData.find(c => c.id === activeConversationId);
    if (!conv) return;

    const activeAvatar = document.getElementById('active-avatar');
    const activeName = document.getElementById('active-name');
    const activeBadge = document.getElementById('active-badge');
    const activeSubtitle = document.getElementById('active-subtitle');

    if (currentRole === 'customer') {
        activeAvatar.src = conv.riderAvatar;
        activeName.textContent = `${conv.riderName} (Delivery Rider)`;
        activeBadge.textContent = 'Assigned Rider';
        activeSubtitle.innerHTML = `Order #${conv.orderNo} • <span class="text-green-600 font-semibold">${conv.status}</span>`;
    } else {
        activeAvatar.src = conv.customerAvatar;
        activeName.textContent = conv.customerName;
        activeBadge.textContent = 'Customer';
        activeSubtitle.innerHTML = `Order #${conv.orderNo} • Delivery to ${conv.address}`;
    }

    const messagesContainer = document.getElementById('chat-messages');
    messagesContainer.innerHTML = '';

    conv.messages.forEach(msg => {
        const isMe = (currentRole === 'customer' && msg.sender === 'customer') || (currentRole === 'rider' && msg.sender === 'rider');
        
        const bubbleWrapper = document.createElement('div');
        bubbleWrapper.className = `flex flex-col ${isMe ? 'items-end' : 'items-start'} animate-fade-in`;

        bubbleWrapper.innerHTML = `
            <div class="max-w-[80%] md:max-w-[65%] rounded-2xl px-4 py-2.5 text-xs md:text-sm shadow-sm ${isMe ? 'bg-darkBlue text-white rounded-br-none' : 'bg-white text-darkBlue border border-gray-200 rounded-bl-none'}">
                <p class="leading-relaxed whitespace-pre-wrap">${escapeHtml(msg.text)}</p>
            </div>
            <span class="text-[10px] text-gray-400 mt-1 px-1">${msg.time} ${isMe ? '• <i class="fa-solid fa-check-double text-primary"></i>' : ''}</span>
        `;
        messagesContainer.appendChild(bubbleWrapper);
    });

    messagesContainer.scrollTop = messagesContainer.scrollHeight;
}

// --- Render Order Panel & Timeline ---
function renderOrderPanel() {
    const conv = conversationsData.find(c => c.id === activeConversationId);
    if (!conv) return;

    document.getElementById('panel-order-no').textContent = `#${conv.orderNo}`;
    document.getElementById('panel-order-status').textContent = conv.status;
    document.getElementById('panel-customer-name').textContent = conv.customerName;
    document.getElementById('panel-rider-name').textContent = conv.riderName;
    document.getElementById('panel-est-time').textContent = `${conv.estArrival} (Today)`;
    document.getElementById('panel-address').textContent = conv.address;

    const itemsList = document.getElementById('panel-items-list');
    itemsList.innerHTML = '';
    conv.items.forEach(item => {
        const div = document.createElement('div');
        div.className = 'flex items-center justify-between text-xs bg-gray-50 p-2.5 rounded-xl border border-gray-100';
        div.innerHTML = `
            <div>
                <span class="font-semibold text-darkBlue block">${item.name}</span>
                <span class="text-gray-400">Qty: ${item.qty}</span>
            </div>
            <span class="font-bold text-darkBlue">${item.price}</span>
        `;
        itemsList.appendChild(div);
    });

    const timelineContainer = document.getElementById('timeline-container');
    timelineContainer.innerHTML = '';

    const currentStatusIndex = timelineSteps.indexOf(conv.status);

    timelineSteps.forEach((step, idx) => {
        const isPassed = idx <= currentStatusIndex;
        const isCurrent = idx === currentStatusIndex;

        const stepEl = document.createElement('div');
        stepEl.className = 'relative flex items-center gap-3 pl-4';
        stepEl.innerHTML = `
            <div class="absolute -left-1.5 w-4 h-4 rounded-full border-2 ${isPassed ? 'bg-darkBlue border-darkBlue text-white' : 'bg-white border-gray-300'} flex items-center justify-center text-[8px]">
                ${isPassed ? '<i class="fa-solid fa-check"></i>' : ''}
            </div>
            <div>
                <h5 class="text-xs font-bold ${isCurrent ? 'text-darkBlue text-sm' : isPassed ? 'text-gray-700' : 'text-gray-400'}">${step}</h5>
                ${isCurrent ? '<p class="text-[10px] text-primary font-semibold">Current Status</p>' : ''}
            </div>
        `;
        timelineContainer.appendChild(stepEl);
    });
}

// --- Render Quick Replies ---
function renderQuickReplies() {
    const container = document.getElementById('quick-replies-container');
    container.innerHTML = '';

    let replies = [];
    if (currentRole === 'customer') {
        replies = [
            "Where are you now po?",
            "Please leave my order at the doorstep/lobby.",
            "Please add extra cream cheese frosting!",
            "Thank you so much Kuya! 🌟"
        ];
    } else {
        replies = [
            "I'm on my way to your location! 🛵",
            "I have arrived at your delivery address! 📍",
            "Your order has been delivered successfully. Enjoy! 🧁",
            "Could you please verify your exact unit or house number?"
        ];
    }

    replies.forEach(reply => {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'px-3 py-1 bg-white hover:bg-darkBlue hover:text-white text-darkBlue border border-gray-200 rounded-full text-xs font-medium transition shadow-xs flex-shrink-0 cursor-pointer';
        btn.onclick = () => sendQuickReply(reply);
        btn.textContent = reply;
        container.appendChild(btn);
    });
}

function sendQuickReply(text) {
    document.getElementById('message-input').value = text;
    handleSendMessage(new Event('submit'));
}

// --- Message Sending & Simulation ---
function handleInputKeyDown(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        handleSendMessage(e);
    }
}

function handleSendMessage(e) {
    if (e) e.preventDefault();
    const input = document.getElementById('message-input');
    const text = input.value.trim();
    if (!text) return;

    const conv = conversationsData.find(c => c.id === activeConversationId);
    if (!conv) return;

    const timeStr = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    const senderRole = currentRole;

    conv.messages.push({
        sender: senderRole,
        text: text,
        time: timeStr
    });

    input.value = '';
    renderActiveChat();
    renderConversationsList();
    playNotificationSound();

    if (senderRole === 'customer') {
        simulateRiderTypingAndReply(conv);
    }
}

function simulateRiderTypingAndReply(conv) {
    const typingIndicator = document.getElementById('typing-indicator');
    const typingText = document.getElementById('typing-text');
    typingText.textContent = `${conv.riderName} is typing...`;
    typingIndicator.classList.remove('hidden');
    typingIndicator.classList.add('flex');

    const messagesContainer = document.getElementById('chat-messages');
    messagesContainer.scrollTop = messagesContainer.scrollHeight;

    setTimeout(() => {
        typingIndicator.classList.add('hidden');
        typingIndicator.classList.remove('flex');

        const replies = [
            "Received po! Thank you so much for ordering with Taste & See! 🧁",
            "Copy Ma'am/Sir! Almost there na po.",
            "Noted po! Will follow your instructions carefully. 🙏",
            "Thank you for the warm message! Enjoy your freshly baked cinnamon buns!"
        ];
        const randomReply = replies[Math.floor(Math.random() * replies.length)];
        const timeStr = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

        conv.messages.push({
            sender: 'rider',
            text: randomReply,
            time: timeStr
        });

        playNotificationSound();
        renderActiveChat();
        renderConversationsList();
        showToast('New Message from ' + conv.riderName, randomReply, 'success');
    }, 2500);
}

// --- Order Status Advancement (Demo) ---
function advanceOrderStatus(newStatus) {
    const conv = conversationsData.find(c => c.id === activeConversationId);
    if (!conv) return;

    conv.status = newStatus;
    renderApp();
    showToast('Order Status Updated', `Order #${conv.orderNo} status changed to: ${newStatus}`, 'success');

    const timeStr = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    conv.messages.push({
        sender: 'rider',
        text: `📌 System Update: Delivery status has been updated to "${newStatus}".`,
        time: timeStr
    });
    renderActiveChat();
}

// --- Utilities ---
function toggleEmojiPicker() {
    const modal = document.getElementById('emoji-modal');
    modal.classList.toggle('hidden');
    modal.classList.toggle('flex');
}

function insertEmoji(emoji) {
    const input = document.getElementById('message-input');
    input.value += emoji;
    input.focus();
    toggleEmojiPicker();
}

function triggerAttachment() {
    showToast('Attachment Simulator', 'Demo attachment uploaded successfully (Photo of delivery location pinned).', 'success');
    const conv = conversationsData.find(c => c.id === activeConversationId);
    if (conv) {
        const timeStr = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        conv.messages.push({
            sender: currentRole,
            text: '📍 [Attached Pin / Delivery Location Photo]',
            time: timeStr
        });
        renderActiveChat();
        renderConversationsList();
    }
}

function showDemoInfo() {
    const modal = document.getElementById('demo-info-modal');
    modal.classList.toggle('hidden');
    modal.classList.toggle('flex');
}

function escapeHtml(string) {
    return String(string).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
