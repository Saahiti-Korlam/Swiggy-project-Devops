# 🛡️ DevSecOps Pipeline – Terraform + Jenkins + SonarQube + OWASP + Trivy + Docker

## 📐 Architecture Overview

```
Local IDE (VS Code)
      │
      ▼
  Terraform  ──── provisions ────►  AWS EC2 + Security Group
      │
      ▼
   GitHub Repository
      │
      ▼
   Jenkins (CI/CD Orchestrator)
      │
      ├──► SonarQube        (Code Quality & Coverage Analysis)
      │
      ├──► OWASP Dependency Check   (Vulnerability Scanning – File System)
      │
      ├──► Trivy FS Scan    (File System Security Scan)
      │
      ├──► Docker Build     (Build Application Image)
      │
      ├──► Trivy Image Scan (Docker Image Security Scan)
      │
      ├──► DockerHub        (Push Image to Registry)
      │
      └──► Docker Container (Deploy & Access via Browser on port 3000)
```

---

## 📋 Table of Contents

1. [Phase 1 – Terraform Infrastructure Setup](#phase-1--terraform-infrastructure-setup)
2. [Phase 2 – Resource Installation Script](#phase-2--resource-installation-script)
3. [Phase 3 – IAM User & AWS CLI Configuration](#phase-3--iam-user--aws-cli-configuration)
4. [Phase 4 – Provision Infrastructure with Terraform](#phase-4--provision-infrastructure-with-terraform)
5. [Phase 5 – Access Jenkins & SonarQube](#phase-5--access-jenkins--sonarqube)
6. [Phase 6 – Install Jenkins Plugins](#phase-6--install-jenkins-plugins)
7. [Phase 7 – Configure Tools in Jenkins](#phase-7--configure-tools-in-jenkins)
8. [Phase 8 – Configure SonarQube Token & Webhook](#phase-8--configure-sonarqube-token--webhook)
9. [Phase 9 – Configure SonarQube & DockerHub in Jenkins](#phase-9--configure-sonarqube--dockerhub-in-jenkins)
10. [Phase 10 – Build the Jenkins Pipeline Job](#phase-10--build-the-jenkins-pipeline-job)
11. [Phase 11 – Access the Application](#phase-11--access-the-application)

---

## Phase 1 – Terraform Infrastructure Setup

> Use Terraform to automatically provision the AWS EC2 instance and Security Group instead of manually creating resources through the console.

### Terraform File Structure

```
project/
├── main.tf          # EC2 instance + Security Group resource definitions
├── provider.tf      # AWS provider configuration
└── resource.sh      # Bootstrapping script (Jenkins + Docker + Trivy installation)
```
#### Note : Check the folder terraform-scripts for the terrform files that are used for this project
### ✅ Phase 1 Summary
Terraform configuration files are created to define the AWS infrastructure — an EC2 instance with a Security Group that opens ports 22 (SSH), 8080 (Jenkins), 9000 (SonarQube), and 3000 (Application). The `resource.sh` bootstrapping script is passed as `user_data` so all tools are auto-installed on first boot.

---

## Phase 2 – Resource Installation Script

> `resource.sh` is a bootstrapping script that runs automatically when the EC2 instance first starts. It installs Jenkins, Docker, SonarQube (as a container), and Trivy.

### `resource.sh`

```bash
#!/bin/bash

sudo apt update -y
sudo apt install -y wget curl gnupg
sudo mkdir -p /etc/apt/keyrings

# ── Install Temurin 17 JDK (required for Jenkins) ──────────────────────────
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | \
  sudo tee /etc/apt/keyrings/adoptium.asc > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb \
$(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | \
  sudo tee /etc/apt/sources.list.d/adoptium.list > /dev/null

sudo apt update -y
sudo apt install -y temurin-17-jdk
java --version

# ── Install Jenkins ─────────────────────────────────────────────────────────
sudo wget -qO /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | \
  sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt update -y
sudo apt install -y jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins
sudo systemctl status jenkins

# ── Install Docker ──────────────────────────────────────────────────────────
sudo apt-get update
sudo apt-get install docker.io -y
sudo usermod -aG docker ubuntu
newgrp docker
sudo chmod 777 /var/run/docker.sock

# ── Run SonarQube as a Docker Container ────────────────────────────────────
docker run -d --name sonar -p 9000:9000 sonarqube:lts-community

# ── Install Trivy ───────────────────────────────────────────────────────────
sudo apt-get install wget apt-transport-https gnupg lsb-release -y

wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | \
  gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb \
$(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list

sudo apt-get update
sudo apt-get install trivy -y
```

### What This Script Installs

| Tool | Version | Purpose |
|---|---|---|
| **Temurin 17 JDK** | 17 | Java runtime required by Jenkins |
| **Jenkins** | Latest stable | CI/CD orchestration |
| **Docker** | `docker.io` | Container engine for building and running images |
| **SonarQube** | `lts-community` | Code quality and coverage analysis (runs as a container on port 9000) |
| **Trivy** | Latest | File system and Docker image vulnerability scanner |

### ✅ Phase 2 Summary
A single bootstrapping script provisions all required tooling on the EC2 instance at launch time. SonarQube runs as a Docker container — no separate server needed. Trivy is installed as a system binary for both filesystem and image scanning within the pipeline.

---

## Phase 3 – IAM User & AWS CLI Configuration

> Create an AWS IAM user with programmatic access, and configure those credentials locally so Terraform can provision resources on your behalf.

### Step 1: Create IAM User in AWS Console

1. Go to **IAM → Users → Create User**
2. Attach policy: `AdministratorAccess`
3. Click **Create User**

### Step 2: Generate Access Keys

1. Click on the newly created user
2. Go to **Security credentials → Create access key**
3. Select **CLI** as the use case
4. Download the `.csv` file — keep it safe, it won't be shown again

### Step 3: Configure AWS CLI in your IDE / Terminal

```bash
aws configure
```

You will be prompted for:

```
AWS Access Key ID [None]:       <paste your access key>
AWS Secret Access Key [None]:   <paste your secret key>
Default region name [None]:     ap-south-1
Default output format [None]:   json
```

### ✅ Phase 3 Summary
An IAM user is created with Administrator access and programmatic credentials. The AWS CLI is configured locally with these credentials so Terraform can authenticate and provision resources on AWS.

---

## Phase 4 – Provision Infrastructure with Terraform

> Run Terraform commands to initialize, plan, and apply the infrastructure defined in your `.tf` files.

### Step 1: Initialize Terraform

Downloads the required AWS provider plugins.

```bash
terraform init
```

### Step 2: Preview the Execution Plan

Shows what resources will be created without actually creating them.

```bash
terraform plan
```

### Step 3: Apply and Provision Resources

Creates all defined resources on AWS automatically.

```bash
terraform apply --auto-approve
```

> ⏳ Wait for the EC2 instance to fully initialize. The `resource.sh` user data script runs automatically on first boot and installs all tools. This may take **3–5 minutes** after the instance reaches the running state.

### Step 4: To Destroy Resources (when done)

```bash
terraform destroy --auto-approve
```

### ✅ Phase 4 Summary
With three Terraform commands, the entire EC2 instance and Security Group are provisioned on AWS. The bootstrapping script runs automatically, installing Jenkins, Docker, SonarQube, and Trivy — no SSH setup required.

---
<img width="955" height="332" alt="instance-1" src="https://github.com/user-attachments/assets/fb73cf66-8c1a-488f-a1e7-e4ea59fe9867" />
<img width="959" height="363" alt="Security-grp" src="https://github.com/user-attachments/assets/3da10012-3e00-4e55-8623-18d6f94501fb" />



## Phase 5 – Access Jenkins & SonarQube

> Once the EC2 instance is running and tools are installed, access both Jenkins and SonarQube via browser.

### Access Jenkins

```
http://<ec2-public-ip>:8080
```

Retrieve the initial admin password:

```bash
cat /var/lib/jenkins/secrets/initialAdminPassword
```

Copy the output, paste it into the Jenkins UI, and set your own username and password.

### Access SonarQube

```
http://<ec2-public-ip>:9000
```

Default credentials:
```
Username: admin
Password: admin
```

> You will be prompted to change the password on first login.

### ✅ Phase 5 Summary
Both Jenkins (port 8080) and SonarQube (port 9000) are accessible via the EC2 public IP. Jenkins is unlocked with the auto-generated password and SonarQube is logged into with default credentials.

---

## Phase 6 – Install Jenkins Plugins

> Install all plugins required for the pipeline stages — code quality, security scanning, Docker builds, and Node.js support.

Navigate to: **Jenkins Dashboard → Manage Jenkins → Plugins → Available Plugins**

Search and install the following:

| Plugin | Purpose |
|---|---|
| **Eclipse Temurin Installer** | Install and manage JDK versions inside Jenkins |
| **Pipeline Stage View** | Visualize each pipeline stage in the UI |
| **SonarQube Scanner** | Integrate SonarQube analysis into pipeline |
| **NodeJS** | Run `npm` commands inside the pipeline |
| **OWASP Dependency-Check** | Scan project dependencies for known CVEs |
| **Docker** | Core Docker integration |
| **Docker Commons** | Shared Docker libraries |
| **Docker Pipeline** | Use Docker commands inside Jenkinsfile |
| **Docker API** | Docker API bindings for Jenkins |
| **docker-build-step** | Docker build as a pipeline step |

> 🔄 Restart Jenkins after all plugins are installed.

### ✅ Phase 6 Summary
All required plugins are installed to support the full DevSecOps pipeline — from code checkout and quality analysis to vulnerability scanning and Docker image builds.

---

## Phase 7 – Configure Tools in Jenkins

> Configure each tool's installation inside Jenkins so the pipeline can reference them by name.

Navigate to: **Jenkins Dashboard → Manage Jenkins → Tools**

---

### JDK Configuration

```
Section      : JDK installations
Name         : jdk17
Auto install : ✅ checked
Source       : Install from adoptium.net
Version      : jdk-17.0.11+9
```

---

### Git Configuration

```
Section      : Git installations
Name         : Default
Auto install : ✅ checked
```

---

### SonarQube Scanner Configuration

```
Section      : SonarQube Scanner installations
Name         : sonar-scanner
Auto install : ✅ checked
Version      : Latest available
```

---

### NodeJS Configuration

```
Section      : NodeJS installations
Name         : node23
Auto install : ✅ checked
Version      : 23.x (or latest)
```

---

### Docker Configuration

```
Section      : Docker installations
Name         : docker
Auto install : ✅ checked
Source       : Download from docker.com
```

---

### OWASP Dependency-Check Configuration

```
Section      : Dependency-Check installations
Name         : owasp-check
Auto install : ✅ checked
Source       : Install from github.com
Version      : Latest available
```

> ⚠️ The **exact names** configured here (`jdk17`, `sonar-scanner`, `node23`, `docker`, `owasp-check`) must match what is referenced in the Jenkinsfile pipeline script. Any mismatch will cause build failures.

### ✅ Phase 7 Summary
All tools are configured in Jenkins with auto-install enabled. Jenkins will automatically download and manage the correct versions of each tool when the pipeline runs.

---

## Phase 8 – Configure SonarQube Token & Webhook

> Generate a SonarQube authentication token, add it to Jenkins credentials, and create a webhook so SonarQube can report quality gate results back to Jenkins.

### Step 1: Generate a Token in SonarQube

1. Go to `http://<ec2-ip>:9000`
2. Navigate to: **Administration → Security → Users**
3. Click the **3 dots (⋮)** next to your user → **Tokens**
4. Create a token:

```
Name       : sonar-token
Expiration : 30 days
```

5. Click **Generate** and copy the token immediately.

> Example token format: `squ_e6d11fa84488e8012e7728235a95962c883282e5`

---

### Step 2: Add SonarQube Token to Jenkins Credentials

Navigate to: **Dashboard → Manage Jenkins → Credentials → System → Global Credentials → Add Credentials**

```
Kind        : Secret text
Secret      : <paste your sonarqube token>
ID          : sonar-token
Description : sonar-token
```

---

### Step 3: Create a Webhook in SonarQube

Navigate to: **Administration → Configuration → Webhooks → Create**

```
Name : jenkins
URL  : http://<jenkins-ip>:8080/sonarqube-webhook/
```

Click **Create**.

> This webhook allows SonarQube to notify Jenkins when a quality gate check passes or fails, enabling the `waitForQualityGate` step in the pipeline to work correctly.

### ✅ Phase 8 Summary
A SonarQube token is generated and stored securely in Jenkins. A webhook is configured in SonarQube to push quality gate results back to Jenkins in real time, enabling the pipeline to pause and wait for the analysis result before proceeding.

---

## Phase 9 – Configure SonarQube & DockerHub in Jenkins

> Link the SonarQube server URL to Jenkins and add DockerHub credentials so the pipeline can push built images.

### Step 1: Configure SonarQube Server URL in Jenkins

Navigate to: **Dashboard → Manage Jenkins → System → SonarQube Servers → SonarQube Installations → Add SonarQube**

```
Name                       : sonar-server
Server URL                 : http://<ec2-ip>:9000
Server authentication token: sonar-token   (select from credentials dropdown)
```

---

### Step 2: Configure DockerHub Credentials in Jenkins

Navigate to: **Dashboard → Manage Jenkins → Credentials → System → Global Credentials → Add Credentials**

```
Kind        : Username with password
Username    : <your-dockerhub-username>
Password    : <your-dockerhub-password-or-token>
ID          : dockerhub_cred
Description : dockerhub_cred
```

> ⚠️ The credential ID `dockerhub_cred` must exactly match the ID referenced in the `withDockerRegistry` block inside the Jenkinsfile.

### ✅ Phase 9 Summary
Jenkins is now connected to SonarQube (with server URL and auth token) and DockerHub (with push credentials). All external integrations are configured and ready for the pipeline to use.

---

## Phase 10 – Build the Jenkins Pipeline Job

> Create the pipeline job in Jenkins and configure the full Jenkinsfile script.

### Step 1: Create the Pipeline Job

1. **Dashboard → New Item**
2. Enter name: `swiggy-app`
3. Select: **Pipeline**
4. Click **OK**

### Step 2: Configure the Pipeline Script

Under the job's **Configure** page, paste the following pipeline script:

```groovy
pipeline {
    agent any
    tools {
        jdk 'jdk17'
        nodejs 'node23'
    }
    environment {
        SCANNER_HOME = tool 'sonar-scanner'
    }
    stages {

        stage('Clean Workspace') {
            steps {
                cleanWs()
            }
        }

        stage('Checkout from Git') {
            steps {
                git branch: 'main', url: 'https://github.com/<your-username>/<your-repo>.git'
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('sonar-server') {
                    sh '''
                        $SCANNER_HOME/bin/sonar-scanner \
                        -Dsonar.projectName=Swiggy \
                        -Dsonar.projectKey=Swiggy
                    '''
                }
            }
        }

        stage('Quality Gate') {
            steps {
                script {
                    waitForQualityGate abortPipeline: false, credentialsId: 'sonar-token'
                }
            }
        }

        stage('Install Dependencies') {
            steps {
                sh "npm install"
            }
        }

        stage('OWASP Dependency Check') {
            steps {
                dependencyCheck additionalArguments: '--scan ./ --disableYarnAudit --disableNodeAudit',
                                odcInstallation: 'owasp-check'
                dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
            }
        }

        stage('Trivy File System Scan') {
            steps {
                sh "trivy fs . > trivyfs.txt"
            }
        }

        stage('Docker Build & Push') {
            steps {
                script {
                    withDockerRegistry(credentialsId: 'dockerhub_cred', toolName: 'docker') {
                        sh "docker build -t swiggy ."
                        sh "docker tag swiggy <your-dockerhub-username>/swiggy:latest"
                        sh "docker push <your-dockerhub-username>/swiggy:latest"
                    }
                }
            }
        }

        stage('Trivy Image Scan') {
            steps {
                sh "trivy image <your-dockerhub-username>/swiggy:latest > trivy.txt"
            }
        }

        stage('Deploy to Container') {
            steps {
                sh 'docker run -d --name swiggy -p 3000:3000 <your-dockerhub-username>/swiggy:latest'
            }
        }
    }
}
```

### Pipeline Stages Explained

| Stage | Tool Used | What It Does |
|---|---|---|
| **Clean Workspace** | Jenkins | Wipes the workspace before each build for a clean state |
| **Checkout from Git** | Git | Pulls the latest code from the GitHub repository |
| **SonarQube Analysis** | SonarQube Scanner | Scans source code for bugs, code smells, and coverage gaps |
| **Quality Gate** | SonarQube Webhook | Pauses pipeline and waits for SonarQube to return a pass/fail result |
| **Install Dependencies** | Node.js / npm | Installs all `package.json` dependencies |
| **OWASP Dependency Check** | OWASP DC | Scans project dependencies (files) for known CVEs |
| **Trivy File System Scan** | Trivy | Scans the project file system for vulnerabilities; output saved to `trivyfs.txt` |
| **Docker Build & Push** | Docker | Builds the Docker image and pushes it to DockerHub |
| **Trivy Image Scan** | Trivy | Scans the built Docker image for OS and library vulnerabilities; output saved to `trivy.txt` |
| **Deploy to Container** | Docker | Runs the image as a container, exposing the app on port 3000 |

### Step 3: Run the Build

Click **Build Now** and monitor each stage in the **Pipeline Stage View**.

### ✅ Phase 10 Summary
The Jenkins pipeline runs 9 stages end-to-end. The source code and file system are scanned by both SonarQube and OWASP before the image is built. The Docker image is then scanned again by Trivy before being pushed to DockerHub and deployed to a container — ensuring security checks at every layer of the build.

---

## Phase 11 – Access the Application

> Once the pipeline completes successfully, the application is live inside a Docker container.
<img width="1920" height="1080" alt="SWiggy-output" src="https://github.com/user-attachments/assets/1160e715-8150-441b-8f12-c8a32a18a2ae" />


### Verify the running container

```bash
docker ps
```

### Access the Application in Browser

```
http://<ec2-public-ip>:3000
```

### View Trivy Scan Reports

```bash
# File system scan report
cat trivyfs.txt

# Docker image scan report
cat trivy.txt
```

### View OWASP Report in Jenkins

After a successful build, click on the job → **OWASP Dependency-Check** report in the left sidebar to view dependency vulnerability details.

### ✅ Phase 11 Summary
The application is deployed and accessible on port 3000. Security scan reports from Trivy (filesystem & image) and OWASP (dependencies) are available both as text files on the server and as published reports in the Jenkins UI.

---

## 🔒 Security Scan Coverage – Summary

| Layer Scanned | Tool | Output File |
|---|---|---|
| Source code quality | SonarQube | Viewable at `http://<ip>:9000` |
| Project dependencies (CVEs) | OWASP Dependency-Check | `dependency-check-report.xml` |
| File system vulnerabilities | Trivy | `trivyfs.txt` |
| Docker image vulnerabilities | Trivy | `trivy.txt` |

---

## 📌 Quick Reference

| Resource | URL / Value |
|---|---|
| Jenkins UI | `http://<ec2-ip>:8080` |
| SonarQube UI | `http://<ec2-ip>:9000` |
| Application | `http://<ec2-ip>:3000` |
| SonarQube Webhook URL | `http://<ec2-ip>:8080/sonarqube-webhook/` |
| Jenkins Initial Password | `/var/lib/jenkins/secrets/initialAdminPassword` |
| DockerHub Credential ID | `dockerhub_cred` |
| SonarQube Credential ID | `sonar-token` |
| SonarQube Server Name (Jenkins) | `sonar-server` |
| OWASP Tool Name (Jenkins) | `owasp-check` |
| JDK Tool Name (Jenkins) | `jdk17` |
| NodeJS Tool Name (Jenkins) | `node23` |
| Docker Tool Name (Jenkins) | `docker` |
