public with sharing class RSAMaskBatch implements Database.Batchable<Id> {

    private String objectName;
    private List<Id> recordIds;
    private List<String> targetFields;
    private String encField;
    private String statusField;

    public RSAMaskBatch(String objectName, List<Id> recordIds, List<String> targetFields,
                        String encField, String statusField) {
        this.objectName = objectName;
        this.recordIds = recordIds;
        this.targetFields = targetFields;
        this.encField = encField;
        this.statusField = statusField;
    }

    public Iterable<Id> start(Database.BatchableContext bc) { return recordIds; }

    public void execute(Database.BatchableContext bc, List<Id> scope) {
        List<RSA_Key_Config__mdt> cfgs = [SELECT Modulus__c, Exponent__c
                                  FROM RSA_Key_Config__mdt
                                  WHERE DeveloperName = 'Default_Key' LIMIT 1];
                            if (cfgs.isEmpty() || String.isBlank(cfgs[0].Modulus__c) || String.isBlank(cfgs[0].Exponent__c)) {
                                throw new RSAMaskException('RSA_Key_Config__mdt Default_Key missing or incomplete.');
                            }
                            String modHex = cfgs[0].Modulus__c.trim();
                            if (modHex.length() != 512) {
                                throw new RSAMaskException('Modulus length is ' + modHex.length() + ', expected 512.');
                            }
                            BigInt modulus = new BigInt(modHex, 16);
                            BigInt exponent = new BigInt(cfgs[0].Exponent__c.trim(), 16);
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectName);
        Map<String, Schema.SObjectField> fieldMap = sot.getDescribe().fields.getMap();

        Set<String> queryFields = new Set<String>{'Id', statusField};
        for (String f : targetFields) queryFields.add(f);

        List<SObject> records = Database.query(
            'SELECT ' + String.join(new List<String>(queryFields), ', ') +
            ' FROM ' + objectName + ' WHERE Id IN :scope');

        List<SObject> toUpdate = new List<SObject>();
        for (SObject record : records) {
            // Idempotency: never re-mask an already masked record
            if ((Boolean) record.get(statusField) == true) continue;

            List<String> lines = new List<String>();
            for (String fieldName : targetFields) {
                String clean = fieldName.trim().toLowerCase();
                Schema.SObjectField sField = fieldMap.get(clean);
                if (sField == null) continue;
                Schema.DescribeFieldResult d = sField.getDescribe();
                if (!d.isUpdateable()) continue;

                Object raw = record.get(clean);
                if (raw != null) lines.add(clean + ':' + String.valueOf(raw));

                if (!d.isNillable() && !d.isDefaultedOnCreate()) record.put(clean, '*****');
                else record.put(clean, null);
            }

            if (!lines.isEmpty()) {
                Blob aesKey = Crypto.generateAESKey(256);
                Blob cipher = Crypto.encryptWithManagedIV('AES256', aesKey,
                                  Blob.valueOf(String.join(lines, '\n')));
                BigInt m = new BigInt(EncodingUtil.convertToHex(aesKey), 16);
                BigInt c = m.modPow(exponent, modulus);
                record.put(encField, c.toHex() + '::' + EncodingUtil.base64Encode(cipher));
            }
            record.put(statusField, true);
            toUpdate.add(record);
        }
        if (!toUpdate.isEmpty()) update toUpdate;
        System.debug('RSA mask CPU ms: ' + Limits.getCpuTime());
    }

    public void finish(Database.BatchableContext bc) {}

    public class RSAMaskException extends Exception {}
}