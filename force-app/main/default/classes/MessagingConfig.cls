public without sharing class MessagingConfig {
  public class Settings {
    public Boolean whatsappEnabled = false;
    public String whatsappProvider = 'Twilio';
    public String whatsappNamedCredential = 'WhatsApp_Graph';
    public String whatsappGraphVersion = 'v24.0';
    public String whatsappPhoneNumberId;
    public String whatsappVerifyToken;
    public String whatsappAppSecret;
    public Boolean requireWebhookSignature = true;
    public String twilioAccountSid;
    public String twilioAuthToken;
    public String twilioFromNumber;
    public String twilioDefaultContentSid;
    public String twilioWebhookPublicUrl;
    public Boolean emailEnabled = false;
    public String emailServiceAddress;
    public String emailFromAddress;
    public String defaultEmailSubject = 'Seguimiento de tu asesor de seguros';
    public Boolean autoCreateLeads = false;
  }

  @TestVisible
  private static Settings testSettings;

  public static Settings getSettings() {
    if (Test.isRunningTest() && testSettings != null) {
      return testSettings;
    }

    Settings settings = new Settings();
    Messaging_Settings__mdt metadata = Messaging_Settings__mdt.getInstance(
      'Default'
    );
    if (metadata == null) {
      return settings;
    }

    settings.whatsappEnabled = metadata.WhatsApp_Enabled__c;
    settings.whatsappProvider = valueOrDefault(
      metadata.WhatsApp_Provider__c,
      settings.whatsappProvider
    );
    settings.whatsappNamedCredential = valueOrDefault(
      metadata.WhatsApp_Named_Credential__c,
      settings.whatsappNamedCredential
    );
    settings.whatsappGraphVersion = valueOrDefault(
      metadata.WhatsApp_Graph_Version__c,
      settings.whatsappGraphVersion
    );
    settings.whatsappPhoneNumberId = metadata.WhatsApp_Phone_Number_ID__c;
    settings.requireWebhookSignature = metadata.Require_Webhook_Signature__c;
    settings.twilioAccountSid = metadata.Twilio_Account_SID__c;
    settings.twilioFromNumber = metadata.Twilio_From_Number__c;
    settings.twilioDefaultContentSid = metadata.Twilio_Default_Content_SID__c;
    settings.twilioWebhookPublicUrl = metadata.Twilio_Webhook_Public_URL__c;
    settings.emailEnabled = metadata.Email_Enabled__c;
    settings.emailServiceAddress = metadata.Email_Service_Address__c;
    settings.emailFromAddress = metadata.Email_From_Address__c;
    settings.defaultEmailSubject = valueOrDefault(
      metadata.Default_Email_Subject__c,
      settings.defaultEmailSubject
    );
    settings.autoCreateLeads = metadata.Auto_Create_Leads__c;

    Messaging_Secrets__c secrets = Messaging_Secrets__c.getOrgDefaults();
    if (secrets != null) {
      settings.whatsappVerifyToken = secrets.WhatsApp_Verify_Token__c;
      settings.whatsappAppSecret = secrets.WhatsApp_App_Secret__c;
      settings.twilioAuthToken = secrets.Twilio_Auth_Token__c;
    }
    return settings;
  }

  private static String valueOrDefault(String value, String defaultValue) {
    return String.isBlank(value) ? defaultValue : value.trim();
  }
}
