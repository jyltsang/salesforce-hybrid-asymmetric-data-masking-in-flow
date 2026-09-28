# salesforce-hybrid-asymmetric-data-masking-in-flow
Salesforce solution for masking PI using RSA2048 + AES256

## Overview
A more secure workflow of the [salesforce-aes256-data-masking-in-flow](https://github.com/jyltsang/salesforce-aes256-data-masking-in-flow) project, this applies an asymmetric approach to manage data, which prevents data exposure during standard operations while mitigating the risk of metadata-based key compromise. It allows Salesforce Administrators to configure targeted data masking via Flows and decrypt exported CSVs entirely off-platform.

## Risk Mitigation
* **Malicious Bulk Data Export:** Mitigates the risk of compromised credentials or rogue connected applications bulk-exporting unencrypted production data via APIs or Data Loader.
* **Insider Threat & Accidental Exposure (Data Minimisation):** Limits the viewing of unnecessary PI at the record UI level, preventing visual exposure to support staff or internal users who do not require access to the raw data.
* **Metadata & Key Exfiltration:** Protects against advanced insider threats who might export system configuration files or Apex classes to steal encryption keys. The Public Key stored in Salesforce is useless for decryption.

## The Improvement From Symmetric to Hybrid Asymmetric Encryption
This project specifically addresses the primary limitation of pure symmetric encryption models.
* **Symmetric Encryption (Previous Approach):** Uses the same AES-256 key to encrypt and decrypt data. 
  * *The Vulnerability:* The encryption key must be stored within Salesforce (e.g., in Apex code, Custom Metadata). **If a malicious actor or insider compromises the environment and exports the metadata, they obtain the key and can decrypt all exfiltrated data.**
* **Hybrid Asymmetric Encryption (This Project):** Uses a two-key architecture. 
  * *The Solution:* Salesforce only holds the **Public Key**, which can *only* encrypt data. The **Private Key**, required for decryption, is kept completely off-platform. Even if a bad actor exports the entire Salesforce database and all metadata, the data remains cryptographically locked.

## Architecture Components
1. **`FlowRSADataMaskingAction.cls`**: An invocable Apex class that generates a per-record AES-256 key, encrypts the targeted field data, wraps the AES key with an RSA-2048 Public Key, stores the envelope in an audit log field, and wipes the original record fields.
2. **`salesforce_csv_decryptor.py`**: An off-platform Python utility that consumes Data Loader exports, uses your local RSA Private Key to unwrap the AES keys, decrypts the payloads, and reconstructs standard CSV columns.

---

## Implementation & Setup
### 1. RSA Key Pair Generation (Off-Platform)
Before deploying the Apex class, you must generate a cryptographically secure RSA key pair. **Do this on a secure local machine.**

Run the following OpenSSL commands in your terminal:
# 1. Generate a 2048-bit RSA Private Key (Keep this secure and strictly off-platform)
```bash
openssl genrsa -out private_key.pem 2048
```

# 2. Extract the Public Key in DER Base64 format (For use inside Salesforce)
```bash
openssl rsa -in private_key.pem -pubout -outform DER | base64 > public_key_base64.txt
```
Copy the Base64 string from public_key_base64.txt and paste it into the RSA_PUBLIC_KEY_PEM constant in the Apex script:
```bash
private static final String RSA_PUBLIC_KEY_PEM = 'YOUR_GENERATED_BASE64_PUBLIC_KEY_HERE';
```
### 2. Create Necessary Salesforce Fields
Create the following fields on your target object (e.g., `Contact` or `Account`):
* **Encrypted Log Field:** Text Area (Rich) maximized to 131,072 characters to store the hybrid encrypted envelope.
* **Status Checkbox Field:** A Checkbox field to track whether the record is currently protected.

### 3. Deploy Apex Classes
Deploy `FlowRSADataMaskingAction.cls` into your Salesforce environment.

### 4. Create the Masking Flow
Because this tool is built as an `@InvocableMethod`, it natively integrates with Salesforce Flows.
1. Create a Flow to retrieve the target records you wish to encrypt.
2. Use an Assignment element to add the API names of the fields you want to mask into a Text Collection variable.
3. Add an Action element pointing to this Apex class.
4. Map the variables:
   * **Object**: Your record collection variable.
   * **Fields Name**: Your text collection of field API names.
   * **Log Field**: The API name of your Rich Text Log Field.
   * **Checkbox Field**: The API name of your Status Checkbox.

### 5. Off-Platform Decryption via Data Loader
When you need to decrypt the data, you must process it outside of Salesforce using the private key:
1. Export the masked records via Salesforce Data Loader, ensuring you include the Record `Id` and the **Encrypted Log Field**. Save as `export.csv`.
2. Run the provided Python utility locally, referencing your private key by using the following command:
```bash
python salesforce_csv_decryptor.py export.csv decrypted_output.csv private_key.pem Encrypted_Log__c
```
The script will automatically unwrap the cryptography and output a clean decrypted_output.csv with distinct columns for every previously masked field. Then you can upload the data back to Salesforce if needed.

