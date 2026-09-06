pipeline {
  agent any

  environment {
    // Matches Terraform var.name — used for tag discovery
    PROJECT   = "jenkins-k8s"
    IMAGE_TAG = "${env.BUILD_NUMBER}"
    APP_DIR   = "app"
  }

  parameters {
    booleanParam(name: 'RUN_SONAR', defaultValue: true, description: 'Run SonarQube analysis')
    booleanParam(name: 'DEPLOY', defaultValue: false, description: 'Deploy to EKS via Ansible SSM (tag Role=ansible)')
  }

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Resolve AWS context') {
      steps {
        script {
          // Region from instance metadata (IMDSv2) — no AWS_REGION parameter
          env.AWS_REGION = sh(
            script: '''
              TOKEN=$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" \
                -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
              curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" \
                http://169.254.169.254/latest/meta-data/placement/region
            ''',
            returnStdout: true
          ).trim()

          // Commit Jenkins built — Ansible checks out the same revision
          env.GIT_COMMIT_SHA = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()

          echo "AWS_REGION=${env.AWS_REGION} PROJECT=${env.PROJECT} GIT_COMMIT=${env.GIT_COMMIT_SHA}"
        }
      }
    }

    stage('Maven Test') {
      steps {
        dir("${APP_DIR}") {
          sh 'mvn -B clean test'
        }
      }
      post {
        always {
          junit allowEmptyResults: true, testResults: 'app/target/surefire-reports/*.xml'
        }
      }
    }

    stage('SonarQube') {
      when {
        expression { return params.RUN_SONAR }
      }
      steps {
        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
          dir("${APP_DIR}") {
            sh '''
              mvn -B verify sonar:sonar \
                -Dsonar.projectKey=marisol-jenkins-kubernetes-cicd \
                -Dsonar.projectName=marisol-jenkins-kubernetes-cicd \
                -Dsonar.host.url=http://127.0.0.1:9000 \
                -Dsonar.token=${SONAR_TOKEN} \
                -Dsonar.qualitygate.wait=true
            '''
          }
        }
      }
    }

    stage('Package') {
      steps {
        dir("${APP_DIR}") {
          sh 'mvn -B -DskipTests package'
        }
      }
    }

    stage('Resolve ECR') {
      steps {
        script {
          // Discover ECR by Project + Role tags (no repository name parameter)
          def ecrArn = sh(
            script: '''
              aws resourcegroupstaggingapi get-resources \
                --region "${AWS_REGION}" \
                --resource-type-filters ecr:repository \
                --tag-filters Key=Project,Values=${PROJECT} Key=Role,Values=ecr \
                --query 'ResourceTagMappingList[0].ResourceARN' \
                --output text
            ''',
            returnStdout: true
          ).trim()
          if (!ecrArn || ecrArn == 'None') {
            error("No ECR repo tagged Project=${env.PROJECT} Role=ecr")
          }
          def repoName = ecrArn.tokenize('/').last()
          env.ECR_REPOSITORY_URL = sh(
            script: """
              aws ecr describe-repositories \
                --region "${AWS_REGION}" \
                --repository-names "${repoName}" \
                --query 'repositories[0].repositoryUri' \
                --output text
            """,
            returnStdout: true
          ).trim()
          echo "Using ECR repository: ${env.ECR_REPOSITORY_URL}"
        }
      }
    }

    stage('Docker Build') {
      steps {
        sh '''
          docker build -t ${ECR_REPOSITORY_URL}:${IMAGE_TAG} ${APP_DIR}
        '''
      }
    }

    stage('Trivy Scan') {
      steps {
        sh '''
          trivy image --scanners vuln --exit-code 1 --severity HIGH,CRITICAL ${ECR_REPOSITORY_URL}:${IMAGE_TAG}
        '''
      }
    }

    stage('Push to ECR') {
      steps {
        sh '''
          aws ecr get-login-password --region ${AWS_REGION} \
            | docker login --username AWS --password-stdin ${ECR_REPOSITORY_URL%/*}
          docker push ${ECR_REPOSITORY_URL}:${IMAGE_TAG}
        '''
      }
    }

    stage('Deploy via Ansible') {
      when {
        expression { return params.DEPLOY }
      }
      steps {
        script {
          // Find Ansible EC2 by Project + Role tags
          env.ANSIBLE_INSTANCE_ID = sh(
            script: '''
              aws ec2 describe-instances \
                --region "${AWS_REGION}" \
                --filters \
                  "Name=tag:Project,Values=${PROJECT}" \
                  "Name=tag:Role,Values=ansible" \
                  "Name=instance-state-name,Values=running" \
                --query 'Reservations[0].Instances[0].InstanceId' \
                --output text
            ''',
            returnStdout: true
          ).trim()
          if (!env.ANSIBLE_INSTANCE_ID || env.ANSIBLE_INSTANCE_ID == 'None') {
            error("No running Ansible instance with tags Project=${env.PROJECT} Role=ansible")
          }

          // Find EKS cluster by Project + Role tags
          def eksArn = sh(
            script: '''
              aws resourcegroupstaggingapi get-resources \
                --region "${AWS_REGION}" \
                --resource-type-filters eks:cluster \
                --tag-filters Key=Project,Values=${PROJECT} Key=Role,Values=eks \
                --query 'ResourceTagMappingList[0].ResourceARN' \
                --output text
            ''',
            returnStdout: true
          ).trim()
          if (!eksArn || eksArn == 'None') {
            error("No EKS cluster tagged Project=${env.PROJECT} Role=eks")
          }
          env.EKS_CLUSTER_NAME = eksArn.tokenize('/').last()
          echo "Deploy Ansible=${env.ANSIBLE_INSTANCE_ID} EKS=${env.EKS_CLUSTER_NAME}"
        }
        // Private GitHub repos can't be cloned on Ansible without creds.
        // Ship ansible/ + k8s/ from this workspace over SSM instead.
        sh '''
          set -euxo pipefail
          tar -czf /tmp/ansible-deploy.tgz ansible k8s
          export BUNDLE_B64
          BUNDLE_B64=$(base64 -w0 /tmp/ansible-deploy.tgz)

          python3 - <<'PY'
import json, os

b64 = os.environ["BUNDLE_B64"]
cmds = [
  "set -euxo pipefail",
  "export HOME=/root",
  "export KUBECONFIG=/root/.kube/config",
  "export EKS_CLUSTER_NAME=%s" % os.environ["EKS_CLUSTER_NAME"],
  "export PATH=/usr/local/bin:/usr/bin:$PATH",
  # Host may still be mid-bootstrap, or older user_data failed on pip upgrade
  "if ! command -v ansible-playbook >/dev/null 2>&1; then dnf install -y python3-pip git unzip >/dev/null; pip3 install --no-cache-dir ansible kubernetes; fi",
  # Install kubectl without nested quotes (Jenkins Groovy is picky about escapes)
  'if ! command -v kubectl >/dev/null 2>&1; then KVER=$(curl -L -s https://dl.k8s.io/release/stable.txt); curl -fsSL -o /usr/local/bin/kubectl https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl; chmod +x /usr/local/bin/kubectl; fi',
  "hash -r",
  "command -v ansible-playbook",
  "command -v kubectl",
  "mkdir -p /opt/ansible",
  "echo '%s' | base64 -d | tar -xzf - -C /opt/ansible" % b64,
  "cd /opt/ansible",
  "ansible-playbook ansible/deploy.yml -e image_tag=%s -e ecr_repository_url=%s"
  % (os.environ["IMAGE_TAG"], os.environ["ECR_REPOSITORY_URL"]),
]
with open("/tmp/deploy-commands.json", "w", encoding="utf-8") as fh:
    json.dump({"commands": cmds}, fh)
PY

          COMMAND_ID=$(aws ssm send-command \
            --region "${AWS_REGION}" \
            --instance-ids "${ANSIBLE_INSTANCE_ID}" \
            --document-name "AWS-RunShellScript" \
            --comment "Deploy ${IMAGE_TAG} to EKS" \
            --parameters file:///tmp/deploy-commands.json \
            --query "Command.CommandId" \
            --output text)

          echo "SSM Command ID: ${COMMAND_ID}"

          # Always fetch logs even when the waiter sees Failed
          set +e
          aws ssm wait command-executed \
            --region "${AWS_REGION}" \
            --command-id "${COMMAND_ID}" \
            --instance-id "${ANSIBLE_INSTANCE_ID}"
          WAIT_RC=$?
          set -e

          STATUS=$(aws ssm get-command-invocation \
            --region "${AWS_REGION}" \
            --command-id "${COMMAND_ID}" \
            --instance-id "${ANSIBLE_INSTANCE_ID}" \
            --query "Status" \
            --output text)

          echo "Ansible deploy status: ${STATUS} (wait_rc=${WAIT_RC})"
          aws ssm get-command-invocation \
            --region "${AWS_REGION}" \
            --command-id "${COMMAND_ID}" \
            --instance-id "${ANSIBLE_INSTANCE_ID}" \
            --query "[StandardOutputContent,StandardErrorContent]" \
            --output text || true

          test "${STATUS}" = "Success"
        '''
      }
    }
  }

  post {
    success {
      echo "Pipeline succeeded. Image: ${env.ECR_REPOSITORY_URL}:${IMAGE_TAG}"
    }
    failure {
      echo "Pipeline failed. Check Maven, Sonar, Trivy, ECR push, or Ansible/EKS deploy."
    }
  }
}
