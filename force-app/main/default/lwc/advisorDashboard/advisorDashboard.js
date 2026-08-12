import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import dashbotLogo from '@salesforce/resourceUrl/DashbotLogo';

import getLeadsWithConversations from '@salesforce/apex/AdvisorDashboardController.getLeadsWithConversations';
import getAppointmentsByDate from '@salesforce/apex/AdvisorDashboardController.getAppointmentsByDate';
import takeLeadConversation from '@salesforce/apex/AdvisorDashboardController.takeConversation';
import getConversations from '@salesforce/apex/ConversationController.getConversations';
import getMessages from '@salesforce/apex/ConversationController.getMessages';
import takeConversationRecord from '@salesforce/apex/ConversationController.takeConversation';

const STATUS_LABELS = {
    online: 'Conversando con IA',
    waiting: 'Esperando respuesta',
    attention: 'Necesita asesor',
    advisor: 'Atendido por ti',
    offline: 'Sin conversación'
};

export default class AdvisorDashboard extends LightningElement {
    activeSection = 'home';
    searchTerm = '';
    selectedProspectId;
    selectedConversationId;
    selectedCalendarDate = new Date().toISOString().slice(0, 10);
    chatMessages = [];
    isLoadingMessages = false;
    messagesError;
    logoUrl = dashbotLogo;
    leadsWired;
    appointmentsWired;
    conversationsWired;
    assistantDraft = '';
    assistantMessages = [
        {
            id: 'welcome',
            role: 'assistant',
            author: 'Dashbot',
            body: 'Puedo ayudarte a capturar y calificar un prospecto. Cuéntame qué necesitas registrar o elige una sugerencia.',
            time: 'Ahora',
            bubbleClass: 'assistant-message assistant'
        }
    ];

    @wire(getLeadsWithConversations)
    wiredLeads(value) {
        this.leadsWired = value;
    }

    @wire(getAppointmentsByDate, { selectedDate: '$selectedCalendarDate' })
    wiredAppointments(value) {
        this.appointmentsWired = value;
    }

    @wire(getConversations)
    wiredConversations(value) {
        this.conversationsWired = value;
    }

    get rawLeads() { return this.leadsWired?.data || []; }
    get rawAppointments() { return this.appointmentsWired?.data || []; }
    get rawConversations() { return this.conversationsWired?.data || []; }
    get isLoading() {
        return [this.leadsWired, this.appointmentsWired, this.conversationsWired]
            .some(value => !value || value.loading);
    }
    get hasError() {
        return [this.leadsWired, this.appointmentsWired, this.conversationsWired]
            .some(value => value?.error);
    }
    get prospects() { return this.rawLeads.map(lead => this.decorateLead(lead)); }
    get conversations() {
        return this.rawConversations.map(conversation => ({
            ...conversation,
            leadName: conversation.Lead__r?.Name || 'Prospecto sin nombre',
            preview: conversation.Last_Message_Preview__c || 'Sin mensajes todavía',
            conversationStatus: conversation.Status__c || 'Bot',
            conversationTime: this.formatRelative(conversation.Last_Message_At__c),
            needsAttention: conversation.Needs_Human_Attention__c === true,
            initials: this.initials(conversation.Lead__r?.Name || 'PS'),
            statusClass: conversation.Needs_Human_Attention__c === true ? 'attention' : '',
            rowClass: `conversation-item${conversation.Id === this.selectedConversationId ? ' selected' : ''}`
        }));
    }
    get appointments() { return this.rawAppointments.map(event => this.decorateEvent(event)); }
    get hasAppointments() { return this.appointments.length > 0; }
    get hasAssistantMessages() { return this.assistantMessages.length > 0; }
    get isHomeSection() { return this.activeSection === 'home'; }
    get isProspectosSection() { return this.activeSection === 'prospectos'; }
    get isConversacionesSection() { return this.activeSection === 'conversaciones'; }
    get isCitasSection() { return this.activeSection === 'citas'; }
    get isAlertasSection() { return this.activeSection === 'alertas'; }
    get filteredProspects() {
        const term = this.searchTerm.trim().toLowerCase();
        if (!term) return this.prospects;
        return this.prospects.filter(prospect => [prospect.name, prospect.channel, prospect.interest, prospect.activity]
            .join(' ').toLowerCase().includes(term));
    }
    get filteredConversations() {
        const term = this.searchTerm.trim().toLowerCase();
        if (!term) return this.conversations;
        return this.conversations.filter(item => [item.leadName, item.preview, item.conversationStatus]
            .join(' ').toLowerCase().includes(term));
    }
    get onlineProspects() { return this.rawLeads.length; }
    get activeConversations() { return this.rawConversations.length; }
    get attentionCount() { return this.rawLeads.filter(lead => lead.Necesita_Atencion__c).length; }
    get todayAppointments() {
        const today = new Date().toISOString().slice(0, 10);
        return this.selectedCalendarDate === today ? this.rawAppointments.length : 0;
    }
    get calendarLabel() {
        return new Date(`${this.selectedCalendarDate}T12:00:00`).toLocaleDateString('es-MX', {
            weekday: 'long', day: 'numeric', month: 'long'
        });
    }
    get calendarShortLabel() {
        return new Date(`${this.selectedCalendarDate}T12:00:00`).toLocaleDateString('es-MX', {
            day: 'numeric', month: 'short'
        });
    }
    get isTodaySelected() { return this.selectedCalendarDate === new Date().toISOString().slice(0, 10); }
    get selectedProspect() {
        return this.prospects.find(item => item.id === this.selectedProspectId) || this.prospects[0] || {
            id: '', name: 'Selecciona un prospecto', initials: '?', channel: '—', interest: '—',
            stage: '—', activity: '—', lastActivity: '—', statusLabel: '—', statusClass: 'status-pill',
            avatarClass: 'avatar', avatarLargeClass: 'avatar avatar-large', needsAttention: false,
            alertReason: '', nextAppointment: 'Sin cita'
        };
    }
    get selectedConversation() {
        return this.rawConversations.find(item => item.Id === this.selectedConversationId);
    }
    get hasSelectedConversation() { return Boolean(this.selectedConversation); }
    get hasSelectedProspect() { return Boolean(this.selectedProspectId); }
    get hasMessages() { return this.chatMessages.length > 0; }
    get navClasses() {
        return ['home', 'prospectos', 'conversaciones', 'citas', 'alertas'].reduce((classes, section) => {
            classes[section] = `nav-item${this.activeSection === section ? ' active' : ''}`;
            return classes;
        }, {});
    }

    handleNavClick(event) { this.activeSection = event.currentTarget.dataset.section; }
    handleSearch(event) { this.searchTerm = event.target.value || ''; }
    handleAssistantInput(event) { this.assistantDraft = event.target.value || ''; }
    handleAssistantKeydown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.submitAssistantPrompt();
        }
    }
    handleAssistantSuggestion(event) { this.assistantDraft = event.currentTarget.dataset.prompt; this.submitAssistantPrompt(); }
    submitAssistantPrompt() {
        const prompt = this.assistantDraft.trim();
        if (!prompt) return;
        this.assistantMessages = [
            ...this.assistantMessages,
            { id: `user-${Date.now()}`, role: 'user', author: 'Tú', body: prompt, time: 'Ahora', bubbleClass: 'assistant-message user' },
            { id: `bot-${Date.now() + 1}`, role: 'assistant', author: 'Dashbot', body: this.assistantReply(prompt), time: 'Ahora', bubbleClass: 'assistant-message assistant' }
        ];
        this.assistantDraft = '';
    }
    assistantReply(prompt) {
        const normalized = prompt.toLowerCase();
        if (normalized.includes('cita') || normalized.includes('agenda')) return 'Claro. Puedo revisar la agenda del día y relacionar la cita con un prospecto. ¿Qué fecha y horario quieres registrar?';
        if (normalized.includes('whatsapp') || normalized.includes('mensaje')) return 'Perfecto. Abre Conversaciones para tomar el chat y continuar con el contexto completo del prospecto.';
        if (normalized.includes('prospecto') || normalized.includes('lead')) return 'Vamos a capturarlo. Necesito nombre, producto de interés, canal de contacto y la necesidad principal.';
        return 'Entendido. Puedo ayudarte a identificar al prospecto, resumir su necesidad o llevarte a la conversación correcta.';
    }
    handleDateChange(event) { this.selectedCalendarDate = event.target.value; }
    shiftCalendar(event) {
        const amount = Number(event.currentTarget.dataset.shift);
        const date = new Date(`${this.selectedCalendarDate}T12:00:00`);
        date.setDate(date.getDate() + amount);
        this.selectedCalendarDate = this.toDateKey(date);
    }
    goToToday() { this.selectedCalendarDate = new Date().toISOString().slice(0, 10); }

    async handleSelectProspect(event) {
        const leadId = event.currentTarget.dataset.id;
        if (!leadId) return;
        this.selectedProspectId = leadId;
        this.activeSection = 'conversaciones';
        await this.loadMessagesForLead(leadId);
    }
    async handleSelectConversation(event) {
        const conversationId = event.currentTarget.dataset.id;
        const conversation = this.rawConversations.find(item => item.Id === conversationId);
        this.selectedConversationId = conversationId;
        this.selectedProspectId = conversation?.Lead__c;
        await this.loadMessages(conversationId);
    }
    async loadMessagesForLead(leadId) {
        const conversation = this.rawConversations.find(item => item.Lead__c === leadId);
        if (conversation) {
            this.selectedConversationId = conversation.Id;
            await this.loadMessages(conversation.Id);
        } else {
            this.selectedConversationId = undefined;
            this.chatMessages = [];
            this.messagesError = undefined;
        }
    }
    async loadMessages(conversationId) {
        this.isLoadingMessages = true;
        this.messagesError = undefined;
        try {
            this.chatMessages = (await getMessages({ conversationId }) || []).map(message => this.decorateMessage(message));
        } catch (error) {
            this.messagesError = error;
            this.chatMessages = [];
        } finally {
            this.isLoadingMessages = false;
        }
    }
    async handleTakeConversation() {
        try {
            if (this.selectedConversationId) {
                await takeConversationRecord({ conversationId: this.selectedConversationId });
            } else if (this.selectedProspectId) {
                await takeLeadConversation({ leadId: this.selectedProspectId });
            }
            await Promise.all([refreshApex(this.leadsWired), refreshApex(this.conversationsWired)]);
        } catch (error) {
            this.messagesError = error;
        }
    }

    decorateLead(lead) {
        const name = `${lead.FirstName || ''} ${lead.LastName || ''}`.trim() || 'Prospecto sin nombre';
        const status = STATUS_LABELS[lead.Estado__c] ? lead.Estado__c : 'offline';
        const attention = lead.Necesita_Atencion__c === true;
        return {
            id: lead.Id, name, initials: this.initials(name), channel: lead.Canal__c || 'WhatsApp',
            interest: lead.Producto_de_Interes__c || 'Interés por definir', stage: lead.Etapa__c || 'Prospecto',
            activity: lead.Actividad_Actual__c || 'Conversación iniciada por Agentforce',
            lastActivity: this.formatRelative(lead.Ultima_Actividad__c), status, needsAttention: attention,
            inConversation: lead.En_Conversacion__c === true, statusLabel: STATUS_LABELS[status],
            alertReason: lead.Razon_Alerta__c || 'El prospecto solicitó hablar con un asesor.',
            nextAppointment: lead.Events?.[0] ? this.formatTime(lead.Events[0].StartDateTime) : 'Sin cita',
            channelIcon: lead.Canal__c === 'Correo' ? 'utility:email' : 'utility:chat',
            avatarClass: `avatar${attention ? ' attention' : ''}`,
            avatarLargeClass: `avatar avatar-large${attention ? ' attention' : ''}`,
            statusClass: `status-pill status-${status}`,
            rowClass: `prospect-row${attention ? ' attention-row' : ''}${lead.Id === this.selectedProspectId ? ' selected-row' : ''}`
        };
    }
    decorateEvent(event) {
        const start = new Date(event.StartDateTime);
        const end = event.EndDateTime ? new Date(event.EndDateTime) : null;
        return {
            id: event.Id, name: event.WhoName || 'Prospecto sin nombre', subject: event.Subject || 'Cita con prospecto',
            time: start.toLocaleTimeString('es-MX', { hour: 'numeric', minute: '2-digit' }),
            endTime: end?.toLocaleTimeString('es-MX', { hour: 'numeric', minute: '2-digit' }) || '',
            channel: 'WhatsApp', initials: this.initials(event.WhoName || 'PS'), whoId: event.WhoId
        };
    }
    decorateMessage(message) {
        const incoming = message.Direction__c === 'Incoming';
        return { id: message.Id, body: message.Body__c || '', sender: message.Sender_Type__c || (incoming ? 'Prospecto' : 'Tú'),
            time: this.formatDateTime(message.Sent_At__c || message.CreatedDate), incoming,
            bubbleClass: `chat-message ${incoming ? 'incoming' : 'outgoing'}` };
    }
    initials(name) { return name.split(' ').filter(Boolean).slice(0, 2).map(word => word[0]).join('').toUpperCase() || '?'; }
    toDateKey(date) { return date.toISOString().slice(0, 10); }
    formatDateTime(value) { return value ? new Date(value).toLocaleTimeString('es-MX', { hour: 'numeric', minute: '2-digit' }) : ''; }
    formatTime(value) { return value ? new Date(value).toLocaleTimeString('es-MX', { hour: 'numeric', minute: '2-digit' }) : 'Sin cita'; }
    formatRelative(value) {
        if (!value) return 'Sin actividad';
        const minutes = Math.max(0, Math.round((Date.now() - new Date(value).getTime()) / 60000));
        if (minutes < 1) return 'Ahora';
        if (minutes < 60) return `Hace ${minutes} min`;
        if (minutes < 1440) return `Hace ${Math.round(minutes / 60)} h`;
        return new Date(value).toLocaleDateString('es-MX', { day: 'numeric', month: 'short' });
    }
}
