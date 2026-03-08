# webMethods IS Package CI/CD Pipeline
### Jenkins + ABE — Windows Server Edition

---

## 📁 Project Structure

```
webmethods-cicd\
├── Jenkinsfile                          # Main pipeline definition
├── abe\
│   ├── build.xml                        # ABE Ant build script (Windows paths)
│   └── acd\
│       └── PACKAGE_NAME.acd             # ACD template — copy & rename per package
├── config\
│   └── environments\
│       ├── DEV.properties
│       ├── SIT.properties
│       ├── UAT.properties
│       └── PROD.properties
├── scripts\
│   ├── Deploy-Package.ps1               # Upload & activate package via IS REST API
│   ├── Backup-Package.ps1               # Export current package before deploy
│   ├── Rollback-Package.ps1             # Re-deploy last backup
│   ├── Health-Check.ps1                 # Post-deploy IS health verification
│   └── Run-Tests.ps1                    # Trigger WmTestSuite unit tests
└── packages\                            # ← Place IS package source here
    └── <YOUR_PACKAGE>\
```

---

## 🚀 Pipeline Stages

```
Validate → Checkout → Load Config → ABE Build → Tests → Backup → Deploy → Health Check
```

---

## ⚙️ Prerequisites — Windows Server

### 1. Jenkins Setup
- **Jenkins** installed as a Windows Service (recommended) or running as a local user
- Jenkins must run under a Windows account that has access to `C:\SoftwareAG11`
- Required plugins:
  - Pipeline (`workflow-aggregator`)
  - Git
  - Credentials Binding
  - Timestamper
  - JUnit

### 2. PowerShell Execution Policy
On the Jenkins agent, run once in an elevated PowerShell prompt:
```powershell
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine
```

### 3. SAG / ABE Installation
- Default install path assumed: `C:\SoftwareAG11`
- ABE must be installed under: `C:\SoftwareAG11\common\AssetBuildEnvironment`
- If installed elsewhere, update `SAG_HOME` in the `Jenkinsfile` environment block

Verify ABE is working:
```cmd
C:\SoftwareAG11\common\AssetBuildEnvironment\ant\bin\ant.bat -version
```

### 4. Java
ABE uses the SAG-bundled JVM. Ensure `JAVA_HOME` in `Jenkinsfile` points to:
```
C:\SoftwareAG11\jvm\jvm
```

### 5. Jenkins Credentials
Add these in **Jenkins → Manage Jenkins → Credentials → Global**:

| Credential ID          | Type               | Description                          |
|------------------------|--------------------|--------------------------------------|
| ~~`WM_GIT_REPO_URL`~~  | *(hardcoded)*      | `https://github.com/Jagadeesh999/TestDeployPackage` — set directly in Jenkinsfile |
| `git-credentials`      | Username/Password  | Git access credentials               |
| `dev-is-credentials`   | Username/Password  | DEV IS Administrator credentials     |
| `sit-is-credentials`   | Username/Password  | SIT IS Administrator credentials     |
| `uat-is-credentials`   | Username/Password  | UAT IS Administrator credentials     |
| `prod-is-credentials`  | Username/Password  | PROD IS Administrator credentials    |

---

## 🏗️ Onboarding a New Package

### Step 1 — Add package source
```
packages\
└── MyPackage\          ← IS package directory
    ├── manifest.v3
    ├── ns\
    └── ...
```

### Step 2 — Create an ACD file
```powershell
# ACD already created for TestDeployPackage at abe\acd\TestDeployPackage.acd
# For a new package, copy and rename the template:
Copy-Item abe\acd\PACKAGE_NAME.acd abe\acd\NewPackageName.acd
# Then replace ${PACKAGE_NAME} inside the file with the actual package name
```

### Step 3 — Update environment config
Edit `config\environments\DEV.properties`:
```properties
is.host=your-dev-is-server
is.port=5555
is.protocol=http
is.admin.user=Administrator
is.credentials.id=dev-is-credentials
```

### Step 4 — Commit and push
```cmd
git add .
git commit -m "feat: add MyPackage CI/CD"
git push origin main
```

### Step 5 — Run the Jenkins pipeline
1. Open Jenkins → your pipeline job
2. Click **Build with Parameters**
3. Set `PACKAGE_NAME = TestDeployPackage`, `TARGET_ENV = DEV`
4. Click **Build**

---

## 🔄 Manual Rollback (PowerShell)

```powershell
.\scripts\Rollback-Package.ps1 `
    -Host     "is-server" `
    -Port     "5555" `
    -User     "Administrator" `
    -Password "manage" `
    -Package  "MyPackage" `
    -BackupDir "dist\backups"
```

---

## 🔒 Security Notes

- Credentials are **never** hardcoded — always via Jenkins Credentials store
- PowerShell scripts use `$ErrorActionPreference = "Stop"` for fail-fast behaviour
- HTTPS is configured for SIT, UAT, and PROD environments
- Consider adding a manual `input` approval step in the Jenkinsfile for PROD deployments

---

## 🛠️ Common Windows Troubleshooting

| Issue | Fix |
|---|---|
| `ant.bat` not found | Verify `ABE_HOME` path in Jenkinsfile matches actual install |
| PowerShell script blocked | Run `Set-ExecutionPolicy RemoteSigned` on the agent |
| IS REST call fails (SSL) | Add `-SkipCertificateCheck` to `Invoke-WebRequest` calls for self-signed certs |
| `Access denied` on package dir | Ensure Jenkins service account has read access to `C:\SoftwareAG11` |
| `JAVA_HOME` error in ABE | Update `JAVA_HOME` in Jenkinsfile to point to SAG JVM |

For self-signed SSL certificates on SIT/UAT, add this to the top of each `.ps1` script:
```powershell
# Allow self-signed certs (use only for internal environments)
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
```
