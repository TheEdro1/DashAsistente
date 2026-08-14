# Twilio WhatsApp — Guía de configuración

Esta guía explica cómo dejar funcionando el canal de WhatsApp de Dashbot
usando el sandbox de Twilio. La integración ya está desplegada en Salesforce;
solo falta configurar Twilio y pegar los valores en Salesforce.

## Lo que necesitas

| Recurso | Dónde lo consigues | Tiempo |
|---|---|---|
| Cuenta Twilio (trial gratis) | https://console.twilio.com/sign-up | 5 min |
| Tu compañero con WhatsApp | Cualquier persona con celular propio | 0 min |
| Salesforce org (ya listo) | `sf org list` muestra `hackathon` | 0 min |

## Paso 1 — Crear cuenta Twilio

1. Ve a https://console.twilio.com/sign-up.
2. Regístrate con tu correo (no requiere tarjeta).
3. Confirma tu número de teléfono personal (Twilio te manda un SMS).
4. Una vez dentro, ve a **Messaging → Try it out → WhatsApp Sandbox**.
5. Apunta estos 3 valores (los necesitarás en el paso 3):
   - **Account SID** (empieza con `AC...`, 34 caracteres hex)
   - **Auth Token** (un string largo; dale clic al ojo 👁 para verlo)
   - **Sandbox From Number** (debe ser `+14155238886`)
   - **Join code** (algo como `join <palabra>-<número>`)

## Paso 2 — Tu compañero se une al sandbox

Pide a tu compañero que:
1. Abra WhatsApp en SU celular (no el tuyo).
2. Cree un contacto nuevo con número `+1 415-523-8886`.
3. Mande el mensaje: `join <código>` (el join code que aparece en la consola de Twilio).
4. Recibirá una respuesta automática confirmando que ya puede recibir mensajes.

> **Importante:** cada vez que Twilio renueva el sandbox, todos deben volver a hacer este paso.

## Paso 3 — Pegar credenciales en Salesforce

Tienes dos opciones. Elige la que prefieras:

### Opción A — Por interfaz (recomendada para ti)

1. En Salesforce, ve a **Setup → Custom Metadata Types → Messaging Setting → Manage records → Default → Edit**.
2. Llena estos campos:
   - `WhatsApp Enabled` = ✅ true
   - `WhatsApp Provider` = `Twilio`
   - `Twilio Account SID` = pega tu Account SID (`AC...`)
   - `Twilio From Number` = `+14155238886`
3. Click Save.
4. Luego ve a **Setup → Custom Settings → Messaging Secrets → Manage → Edit (Default Organization Level)**.
5. Llena:
   - `Twilio Auth Token` = pega tu Auth Token.
6. Click Save.

### Opción B — Por terminal

Corre esto (reemplaza los placeholders):

```bash
# Update custom metadata
sf data update record --target-org hackathon --sobject Messaging_Settings__mdt --record-id <DefaultId> --values "WhatsApp_Provider__c=Twilio WhatsApp_Enabled__c=true Twilio_Account_SID__c=ACxxxxx Twilio_From_Number__c=+14155238886"

# Update secrets
sf data update record --target-org hackathon --sobject Messaging_Secrets__c --record-id <SecretsId> --values "Twilio_Auth_Token__c=tu-token-aqui"
```

Para encontrar los IDs:

```bash
sf data query --query "SELECT Id, DeveloperName FROM Messaging_Settings__mdt" --target-org hackathon
sf data query --query "SELECT Id, SetupOwnerId FROM Messaging_Secrets__c" --target-org hackathon
```

## Paso 4 — Crear el Site público para el webhook

Twilio necesita mandar POST a un endpoint público. Salesforce tiene que exponer
`/services/apexrest/messaging/twilio/` a través de un Site.

### 4.1 Crear el Site

1. **Setup → Digital Experiences → Sites** (o buscar "Sites" en Quick Find).
2. Click **New**.
3. Marca la casilla "Active".
4. **Site label**: `Dashbot Twilio Webhook`.
5. **Site name** (URL): `dashbot-twilio` (único en la org).
6. **Default Site Landing Page**: deja vacío o selecciona cualquier página.
7. Click Save.

### 4.2 Habilitar Apex REST en el Site Guest User

1. Click en el Site recién creado.
2. Click **Public Access Settings** → **Enabled Apex Class Access**.
3. Agrega estas 3 clases:
   - `TwilioWebhookController`
   - `ConversationMessagingService`
   - `WhatsAppWebhookController` (si también quieres Meta funcionando)
4. Click Save.

> **Nota:** esta configuración NO se puede hacer vía CLI ni metadata API.
> Hay que hacerlo manualmente en el Setup UI. Es el único paso manual
> del flujo.

### 4.3 Anotar la URL pública

La URL del webhook (configurada en `Messaging_Settings__mdt.Twilio_Webhook_Public_URL__c`) es:

```
https://<tu-org-domain>.develop.my.salesforce-sites.com/services/apexrest/messaging/twilio/
```

Para la org actual (`hackathon`):

```
https://orgfarm-30c191d40a-dev-ed.develop.my.salesforce-sites.com/services/apexrest/messaging/twilio/
```

> Esta URL DEBE coincidir exactamente con la que configures en Twilio,
> porque Twilio la usa para calcular la firma `X-Twilio-Signature`.
> Si usas un dominio custom (Branded URL), actualiza `Twilio_Webhook_Public_URL__c`.

## Paso 5 — Configurar el webhook en Twilio

1. En la consola Twilio, ve a **Messaging → Try it out → WhatsApp Sandbox**.
2. Sección **"When a message comes in"**:
   - **URL**: pega la URL exacta del paso 4.3
   - **Method**: `POST`
3. Sección **"Status callback URL"** (más abajo en la misma pantalla):
   - **URL**: pega la MISMA URL
4. Guarda.

Twilio ahora mandará cada mensaje de tu compañero a Salesforce, y también
notificará cada cambio de estado (queued → sent → delivered → read → failed).

## Paso 6 — Probar

1. Tu compañero abre WhatsApp → envía `Hola` al contacto `+1 415-523-8886`.
2. En Salesforce, abre cualquier Conversation__c con `Channel__c = 'WhatsApp'` —
   debe aparecer un Message__c con `Direction__c = 'Incoming'`.
3. Para probar el flujo de salida:
   - En el dashboard Dashbot, abre la conversación del compañero.
   - Click "Tomar conversación" → escribe algo → Enviar.
   - Tu compañero debe recibir el mensaje en WhatsApp.

## Solución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| Salesforce devuelve 401 sin firma | Endpoint expuesto OK, falta firma | Normal — Twilio siempre manda firma |
| Salesforce devuelve 401 con firma | URL en Twilio ≠ `Twilio_Webhook_Public_URL__c` | Pega la URL exacta del paso 4.3 en Twilio |
| Salesforce devuelve 401 con firma | Auth Token en `Messaging_Secrets__c` ≠ Twilio | Re-pega el Auth Token |
| Salesforce devuelve 503 | `WhatsApp_Provider__c` no es `Twilio` | Edita el Custom Metadata |
| Mensaje no se crea en Salesforce | Site no expone la clase REST | Verifica paso 4.2 (3 clases enabled) |
| Twilio manda "channel not approved" | Tu compañero no se unió al sandbox | Repite paso 2 |
| El asesor no recibe respuestas | Falta activar el agente | `sf agent activate --target-org hackathon --api-name Asistente_Financiero` |
| `requestBody` aparece vacío en logs | Salesforce Sites consume form body | Usar `RestContext.request.params` (ya implementado) |

## Para la demo con jurado

1. Compañero: envía `Hola, me interesa un seguro de vida` desde su WhatsApp.
2. Agente (Agentforce) responde automáticamente.
3. Mostrar al jurado:
   - WhatsApp del compañero (lado del cliente)
   - Dashboard Dashbot (lado del asesor)
4. La "cara del agente" (avatar con gradiente azul) es visible en el header del chat.

## Cuando Meta te apruebe la verificación

Si más adelante Meta te aprueba el business verification, puedes migrar
cambiando solo dos valores en Salesforce:

```bash
# Cambia el provider
sf data update record --target-org hackathon --sobject Messaging_Settings__mdt --record-id <DefaultId> --values "WhatsApp_Provider__c=Meta"

# Configura los valores de Meta
sf data update record --target-org hackathon --sobject Messaging_Settings__mdt --record-id <DefaultId> --values "WhatsApp_Phone_Number_ID__c=1192626727275241 WhatsApp_Graph_Version__c=v26.0 WhatsApp_Named_Credential__c=WhatsApp_Graph"

sf data update record --target-org hackathon --sobject Messaging_Secrets__c --record-id <SecretsId> --values "WhatsApp_App_Secret__c=ff0a2109ee73c46c1b907ede8f5905bb WhatsApp_Verify_Token__c=d43f825b817a42b198d37954446289b4"
```

Sin tocar código. La clase `WhatsAppCloudApiClient` ya está en el repo y se
activará automáticamente cuando el provider sea `Meta`.

## Funcionalidades adicionales implementadas

### Status callbacks (cambio 2)

Twilio ahora actualiza automáticamente el estado de cada mensaje saliente:

| Estado | Significado |
|---|---|
| `Sent` | API aceptó el mensaje |
| `Delivered` | Llegó al celular del destinatario |
| `Read` | El destinatario abrió el mensaje |
| `Failed` | Twilio no pudo entregarlo (mostrará código de error) |

Esto se actualiza en el campo `Status__c` del `Message__c`. El dashboard
mostrará el ícono correspondiente junto a cada mensaje.

### Content templates (cambio 3)

Para mensajes fuera de la ventana de 24h (donde WhatsApp bloquea texto libre),
puedes usar templates aprobados:

1. Crea el template en Twilio Console → Messaging → Content Template Builder.
2. Apunta el `ContentSid` que te da Twilio (formato `HX + 32 hex`).
3. Pega el SID en el campo `Twilio Default Content SID` del Custom Metadata.
4. Cuando el agente necesite mandar fuera de la ventana, invocará el template.

Para usar el template desde Apex:
```java
TwilioWhatsAppClient.SendResult result = TwilioWhatsAppClient.sendTemplate(
  '+5215537950127',
  'HXb5b62575e6e4ff6129ad7c8efe1f983e',
  new Map<String, String>{ '1' => '12/1', '2' => '3pm' }
);
```

### Prefijo `whatsapp:` (cambio 1)

Todas las llamadas a Twilio usan el formato estándar `whatsapp:+E164`. Cuando
migres a producción con un número Business de Meta, no hay que tocar código.

## Resumen de lo implementado

| Funcionalidad | Estado | Tests |
|---|---|---|
| Recepción de mensajes entrantes | ✅ | `processesValidSignedWebhook` |
| Validación de firma `X-Twilio-Signature` | ✅ | `rejectsRequestWithInvalidSignature` |
| Soporte para `request.params` (Salesforce Sites) | ✅ | Incluido en `processesValidSignedWebhook` |
| URL pública configurable (`Twilio_Webhook_Public_URL__c`) | ✅ | Permite match exacto con URL en Twilio |
| Envío de mensajes con prefijo `whatsapp:` | ✅ | `sendsTwilioAndStoresSid` |
| Envío con content templates | ✅ | `sendsTemplateWithContentSidAndVariables` |
| Validación de formato HX de ContentSid | ✅ | `rejectsMalformedContentSid` |
| Status callbacks (delivered/failed) | ✅ | `processesDeliveryStatusCallback`, `processesFailedStatusCallback` |
| Rechazo cuando provider != Twilio | ✅ | `rejectsWhenProviderIsNotTwilio` |

Total: 9 tests Twilio + 9 tests ConversationMessagingService + 4 tests WhatsApp = **22 tests pasan**.

## Verificación end-to-end (2026-08-13)

Probado manualmente con curl firmado contra el endpoint público:

```bash
$ curl -s -w "\nHTTP %{http_code}\n" -X POST \
    'https://orgfarm-30c191d40a-dev-ed.develop.my.salesforce-sites.com/services/apexrest/messaging/twilio/' \
    -H 'X-Twilio-Signature: sha1=<firma calculada>' \
    --data 'Body=Test%20final&From=%2B5215537950127&MessageSid=SMfinal-verify-1&...'
EVENT_RECEIVED
HTTP 200
```

Y el `Message__c` creado:

```
Id          | Body__c         | Direction__c | Status__c
------------|-----------------|--------------|-----------
a01gK...    | Test final      | Incoming     | Received
```
