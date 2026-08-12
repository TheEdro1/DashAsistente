public with sharing class AdvisorDashboardController {

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getLeadsWithConversations() {
        List<Lead> leads = [
            SELECT Id, FirstName, LastName,
                   Edad__c, Tiene_Hijos__c, Presupuesto_Mensual__c,
                   Producto_de_Interes__c, Edades_Hijos__c,
                   Canal__c, Estado__c, Etapa__c,
                   Actividad_Actual__c, Necesita_Atencion__c,
                   En_Conversacion__c, Razon_Alerta__c,
                   Ultima_Actividad__c,
                   (
                       SELECT Id, Subject, StartDateTime, EndDateTime
                       FROM Events
                       WHERE StartDateTime >= :DateTime.now()
                       ORDER BY StartDateTime ASC
                       LIMIT 1
                   )
            FROM Lead
            WHERE IsConverted = false
            ORDER BY Ultima_Actividad__c DESC NULLS LAST
            LIMIT 50
        ];

        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Lead l : leads) {
            Map<String, Object> row = new Map<String, Object>();
            row.put('Id', l.Id);
            row.put('FirstName', l.FirstName);
            row.put('LastName', l.LastName);
            row.put('Edad__c', l.Edad__c);
            row.put('Tiene_Hijos__c', l.Tiene_Hijos__c);
            row.put('Presupuesto_Mensual__c', l.Presupuesto_Mensual__c);
            row.put('Producto_de_Interes__c', l.Producto_de_Interes__c);
            row.put('Edades_Hijos__c', l.Edades_Hijos__c);
            row.put('Canal__c', l.Canal__c);
            row.put('Estado__c', l.Estado__c);
            row.put('Etapa__c', l.Etapa__c);
            row.put('Actividad_Actual__c', l.Actividad_Actual__c);
            row.put('Necesita_Atencion__c', l.Necesita_Atencion__c);
            row.put('En_Conversacion__c', l.En_Conversacion__c);
            row.put('Razon_Alerta__c', l.Razon_Alerta__c);
            row.put('Ultima_Actividad__c', l.Ultima_Actividad__c);

            List<Map<String, Object>> events = new List<Map<String, Object>>();
            if (l.Events != null) {
                for (Event e : l.Events) {
                    Map<String, Object> evt = new Map<String, Object>();
                    evt.put('Id', e.Id);
                    evt.put('Subject', e.Subject);
                    evt.put('StartDateTime', e.StartDateTime);
                    evt.put('EndDateTime', e.EndDateTime);
                    events.add(evt);
                }
            }
            row.put('Events', events);
            result.add(row);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getAppointmentsByDate(Date selectedDate) {
        Date appointmentDate = selectedDate == null ? Date.today() : selectedDate;
        List<Event> events = [
            SELECT Id, Subject, StartDateTime, EndDateTime, WhoId
            FROM Event
            WHERE ActivityDate = :appointmentDate
              AND WhoId != null
            ORDER BY StartDateTime ASC
            LIMIT 20
        ];

        List<Map<String, Object>> result = new List<Map<String, Object>>();
        Map<Id, Lead> leadsById = new Map<Id, Lead>();
        Set<Id> whoIds = new Set<Id>();
        for (Event e : events) {
            whoIds.add(e.WhoId);
        }
        if (!whoIds.isEmpty()) {
            for (Lead l : [SELECT Id, FirstName, LastName FROM Lead WHERE Id IN :whoIds]) {
                leadsById.put(l.Id, l);
            }
        }

        for (Event e : events) {
            Map<String, Object> row = new Map<String, Object>();
            row.put('Id', e.Id);
            row.put('Subject', e.Subject);
            row.put('StartDateTime', e.StartDateTime);
            row.put('EndDateTime', e.EndDateTime);
            row.put('WhoId', e.WhoId);
            Lead who = leadsById.get(e.WhoId);
            if (who != null) {
                row.put(
                    'WhoName',
                    ((who.FirstName != null ? who.FirstName : '') + ' ' + (who.LastName != null ? who.LastName : '')).trim()
                );
            } else {
                row.put('WhoName', '—');
            }
            result.add(row);
        }
        return result;
    }

    @AuraEnabled
    public static void takeConversation(Id leadId) {
        if (leadId == null) {
            throw new AuraHandledException('leadId is required');
        }
        update new Lead(
            Id = leadId,
            Estado__c = 'advisor',
            Necesita_Atencion__c = false,
            En_Conversacion__c = true,
            Actividad_Actual__c = 'Conversación tomada por el asesor',
            Ultima_Actividad__c = DateTime.now(),
            Razon_Alerta__c = null
        );
    }
}
