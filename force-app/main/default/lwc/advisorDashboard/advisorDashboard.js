import { LightningElement } from 'lwc';

export default class AdvisorDashboard extends LightningElement {

    searchTerm = '';
    selectedProspectId = 'p4';

    prospects = [
        {
            id: 'p1',
            name: 'María Fernanda Ríos',
            initials: 'MR',
            channel: 'WhatsApp',
            interest: 'Seguro de vida',
            stage: 'Análisis',
            status: 'online',
            statusLabel: 'En conversación',
            activity: 'Agendando cita',
            lastActivity: 'Hace 1 min',
            nextAppointment: 'Hoy, 10:00 AM',
            needsAttention: false,
            inConversation: true,
            alertReason: ''
        },
        {
            id: 'p2',
            name: 'Juan Carlos López',
            initials: 'JL',
            channel: 'Correo',
            interest: 'Protección familiar',
            stage: 'Prospecto',
            status: 'online',
            statusLabel: 'En conversación',
            activity: 'Hablando con el bot',
            lastActivity: 'Hace 2 min',
            nextAppointment: 'Hoy, 12:00 PM',
            needsAttention: false,
            inConversation: true,
            alertReason: ''
        },
        {
            id: 'p3',
            name: 'Andrea Velázquez',
            initials: 'AV',
            channel: 'WhatsApp',
            interest: 'Ahorro e inversión',
            stage: 'Análisis',
            status: 'waiting',
            statusLabel: 'Esperando respuesta',
            activity: 'El bot hizo una pregunta',
            lastActivity: 'Hace 4 min',
            nextAppointment: 'Sin cita',
            needsAttention: false,
            inConversation: true,
            alertReason: ''
        },
        {
            id: 'p4',
            name: 'Diego Ortega',
            initials: 'DO',
            channel: 'WhatsApp',
            interest: 'Seguro de vida',
            stage: 'Evaluación',
            status: 'attention',
            statusLabel: 'Requiere atención',
            activity: 'Solicitó hablar con un asesor',
            lastActivity: 'Hace 1 min',
            nextAppointment: 'Mañana, 9:00 AM',
            needsAttention: true,
            inConversation: true,
            alertReason: 'El bot detectó necesidad de intervención humana'
        },
        {
            id: 'p5',
            name: 'Sofía Carmona',
            initials: 'SC',
            channel: 'WhatsApp',
            interest: 'Seguro familiar',
            stage: 'Análisis',
            status: 'online',
            statusLabel: 'En conversación',
            activity: 'Agendando cita',
            lastActivity: 'Hace 3 min',
            nextAppointment: 'Hoy, 3:30 PM',
            needsAttention: false,
            inConversation: true,
            alertReason: ''
        },
        {
            id: 'p6',
            name: 'Luis Ramírez',
            initials: 'LR',
            channel: 'Correo',
            interest: 'Plan de retiro',
            stage: 'Prospecto',
            status: 'online',
            statusLabel: 'En conversación',
            activity: 'Hablando con el bot',
            lastActivity: 'Hace 5 min',
            nextAppointment: 'Mañana, 11:30 AM',
            needsAttention: false,
            inConversation: true,
            alertReason: ''
        },
        {
            id: 'p7',
            name: 'Mónica Galindo',
            initials: 'MG',
            channel: 'WhatsApp',
            interest: 'Protección patrimonial',
            stage: 'Análisis',
            status: 'waiting',
            statusLabel: 'Esperando respuesta',
            activity: 'El bot hizo una pregunta',
            lastActivity: 'Hace 7 min',
            nextAppointment: 'Sin cita',
            needsAttention: false,
            inConversation: true,
            alertReason: ''
        },
        {
            id: 'p8',
            name: 'Felipe Paredes',
            initials: 'FP',
            channel: 'WhatsApp',
            interest: 'Seguro de vida',
            stage: 'Evaluación',
            status: 'attention',
            statusLabel: 'Requiere atención',
            activity: 'Tiene una duda fuera del Knowledge',
            lastActivity: 'Hace 8 min',
            nextAppointment: 'Viernes, 1:00 PM',
            needsAttention: true,
            inConversation: false,
            alertReason: 'Agentforce no encontró información suficiente para responder'
        },
        {
            id: 'p9',
            name: 'Carolina Zamora',
            initials: 'CZ',
            channel: 'Correo',
            interest: 'Seguro educativo',
            stage: 'Prospecto',
            status: 'online',
            statusLabel: 'En conversación',
            activity: 'Revisando información',
            lastActivity: 'Hace 9 min',
            nextAppointment: 'Sin cita',
            needsAttention: false,
            inConversation: false,
            alertReason: ''
        },
        {
            id: 'p10',
            name: 'Valentina Ruiz',
            initials: 'VR',
            channel: 'WhatsApp',
            interest: 'Seguro de vida',
            stage: 'Evaluación',
            status: 'attention',
            statusLabel: 'Requiere atención',
            activity: 'Solicitó atención humana',
            lastActivity: 'Hace 10 min',
            nextAppointment: 'Mañana, 4:00 PM',
            needsAttention: true,
            inConversation: true,
            alertReason: 'El prospecto solicitó expresamente hablar con un asesor'
        }
    ];

    appointments = [
        {
            id: 'a1',
            name: 'María Fernanda Ríos',
            date: 'Hoy, 10:00 AM',
            channel: 'WhatsApp',
            channelClass: 'channel-pill whatsapp',
            today: true
        },
        {
            id: 'a2',
            name: 'Juan Carlos López',
            date: 'Hoy, 12:00 PM',
            channel: 'Correo',
            channelClass: 'channel-pill email',
            today: true
        },
        {
            id: 'a3',
            name: 'Sofía Carmona',
            date: 'Hoy, 3:30 PM',
            channel: 'WhatsApp',
            channelClass: 'channel-pill whatsapp',
            today: true
        },
        {
            id: 'a4',
            name: 'Diego Ortega',
            date: 'Hoy, 5:00 PM',
            channel: 'WhatsApp',
            channelClass: 'channel-pill whatsapp',
            today: true
        },
        {
            id: 'a5',
            name: 'Mónica Galindo',
            date: 'Hoy, 6:00 PM',
            channel: 'WhatsApp',
            channelClass: 'channel-pill whatsapp',
            today: true
        },
        {
            id: 'a6',
            name: 'Felipe Paredes',
            date: 'Hoy, 7:30 PM',
            channel: 'Correo',
            channelClass: 'channel-pill email',
            today: true
        }
    ];


    // ================================
    // MÉTRICAS
    // ================================

    get onlineProspects() {
        return this.prospects.length;
    }

    get activeConversations() {
        return this.prospects.filter(
            prospect => prospect.inConversation
        ).length;
    }

    get attentionCount() {
        return this.prospects.filter(
            prospect => prospect.needsAttention
        ).length;
    }

    get todayAppointments() {
        return this.appointments.filter(
            appointment => appointment.today
        ).length;
    }


    // ================================
    // PROSPECTOS
    // ================================

    get filteredProspects() {

        const search = this.searchTerm
            .trim()
            .toLowerCase();

        let result = this.prospects;

        if (search) {
            result = this.prospects.filter(prospect => {

                const searchableText = [
                    prospect.name,
                    prospect.channel,
                    prospect.interest,
                    prospect.activity,
                    prospect.stage,
                    prospect.statusLabel
                ]
                    .join(' ')
                    .toLowerCase();

                return searchableText.includes(search);
            });
        }

        return result.map(prospect =>
            this.decorateProspect(prospect)
        );
    }

    get filteredProspectCount() {
        return this.filteredProspects.length;
    }


    // ================================
    // ALERTAS
    // ================================

    get attentionProspects() {

        return this.prospects
            .filter(prospect => prospect.needsAttention)
            .map(prospect => this.decorateProspect(prospect));

    }


    // ================================
    // PROSPECTO SELECCIONADO
    // ================================

    get selectedProspect() {

        const prospect =
            this.prospects.find(
                item => item.id === this.selectedProspectId
            ) || this.prospects[0];

        return this.decorateProspect(prospect);
    }


    // ================================
    // DECORACIÓN VISUAL
    // ================================

    decorateProspect(prospect) {

        const isSelected =
            prospect.id === this.selectedProspectId;

        let rowClass = 'prospect-row';

        if (prospect.needsAttention) {
            rowClass += ' attention-row';
        }

        if (isSelected) {
            rowClass += ' selected-row';
        }


        let avatarClass = 'prospect-avatar';

        if (prospect.needsAttention) {
            avatarClass += ' attention-avatar';
        }


        let statusClass = 'status-pill';

        if (prospect.status === 'online') {
            statusClass += ' status-online';
        }

        if (prospect.status === 'waiting') {
            statusClass += ' status-waiting';
        }

        if (prospect.status === 'attention') {
            statusClass += ' status-attention';
        }

        if (prospect.status === 'advisor') {
            statusClass += ' status-advisor';
        }


        const channelIcon =
            prospect.channel === 'Correo'
                ? 'utility:email'
                : 'utility:chat';


        return {
            ...prospect,

            rowClass,
            avatarClass,

            avatarLargeClass:
                prospect.needsAttention
                    ? 'summary-avatar attention-avatar'
                    : 'summary-avatar',

            statusClass,
            channelIcon
        };
    }


    // ================================
    // BÚSQUEDA
    // ================================

    handleSearch(event) {
        this.searchTerm = event.target.value;
    }


    // ================================
    // SELECCIONAR PROSPECTO
    // ================================

    handleSelectProspect(event) {

        const prospectId =
            event.currentTarget.dataset.id;

        this.selectedProspectId = prospectId;
    }


    // ================================
    // TOMAR CONVERSACIÓN
    // ================================

    handleTakeConversation(event) {

        const prospectId =
            event.currentTarget.dataset.id;

        if (!prospectId) {
            return;
        }


        this.selectedProspectId = prospectId;


        this.prospects = this.prospects.map(prospect => {

            if (prospect.id !== prospectId) {
                return prospect;
            }


            return {
                ...prospect,

                needsAttention: false,

                status: 'advisor',

                statusLabel: 'Atendido por ti',

                activity:
                    'Conversación tomada por el asesor',

                lastActivity: 'Ahora',

                alertReason: ''
            };
        });
    }
}