public with sharing class FlowRSADataMaskingAction {

    public class MaskRequest {
        @InvocableVariable(required=true label='Object' description='Collection of records to encrypt')
        public List<SObject> recordsToMask;
        @InvocableVariable(required=true label='Fields Name' description='Collection of field API names to encrypt')
        public List<String> fieldNamesCollection;
        @InvocableVariable(required=true label='Log Field' description='API Name of the rich text log field')
        public String encryptedLogFieldName;
        @InvocableVariable(required=true label='Checkbox Field' description='API Name of the status checkbox field')
        public String statusCheckboxFieldName;
    }

    public class MaskResult {
        @InvocableVariable(label='Success Flag') public Boolean isSuccess;
        @InvocableVariable(label='Message') public String message;
    }

    // Flow entry point: validates, then hands off to an async batch (one record per transaction)
    @InvocableMethod(label='Asymmetrical RSA Masking (Async)' description='Queues RSA hybrid masking; one record per batch scope.')
    public static List<MaskResult> processRecords(List<MaskRequest> requests) {
        List<MaskResult> results = new List<MaskResult>();
        for (MaskRequest req : requests) {
            MaskResult res = new MaskResult();
            try {
                if (req == null || req.recordsToMask == null || req.recordsToMask.isEmpty()) {
                    res.isSuccess = false;
                    res.message = 'ERROR: The record collection is empty.';
                } else {
                    Set<Id> ids = new Set<Id>();
                    for (SObject s : req.recordsToMask) { if (s.Id != null) ids.add(s.Id); }
                    if (ids.isEmpty()) {
                        res.isSuccess = false;
                        res.message = 'ERROR: Provided records must have valid IDs.';
                    } else {
                        String objectName = req.recordsToMask[0].getSObjectType().getDescribe().getName();
                        Id jobId = Database.executeBatch(new RSAMaskBatch(
                            objectName, new List<Id>(ids),
                            resolveFieldNames(req.fieldNamesCollection),
                            req.encryptedLogFieldName.trim(),
                            req.statusCheckboxFieldName.trim()), 1);
                        res.isSuccess = true;
                        res.message = 'QUEUED: ' + ids.size() + ' record(s), batch job ' + jobId;
                    }
                }
            } catch (Exception e) {
                res.isSuccess = false;
                res.message = 'ERROR: ' + e.getMessage();
            }
            results.add(res);
        }
        return results;
    }

    public static List<String> resolveFieldNames(List<String> fieldNames) {
        List<String> resolved = new List<String>();
        if (fieldNames == null) return resolved;
        for (String f : fieldNames) {
            if (String.isBlank(f)) continue;
            String lower = f.trim().toLowerCase();
            if (lower == 'mailingaddress') {
                resolved.addAll(new List<String>{'MailingStreet','MailingCity','MailingState','MailingPostalCode','MailingCountry'});
            } else if (lower == 'billingaddress') {
                resolved.addAll(new List<String>{'BillingStreet','BillingCity','BillingState','BillingPostalCode','BillingCountry'});
            } else {
                resolved.add(f.trim());
            }
        }
        return resolved;
    }
}