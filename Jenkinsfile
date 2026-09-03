pipeline {
  agent any

  environment {
    AWS_REGION          = "${params.AWS_REGION}"
    ECR_REPOSITORY_URL  = "${params.ECR_REPOSITORY_URL}"
    ANSIBLE_INSTANCE_ID = "${params.ANSIBLE_INSTANCE_ID}"
    IMAGE_TAG           = "${env.BUILD_NUMBER}"
    APP_DIR             = "app"
  }

  parameters {
    string(name: 'AWS_REGION', defaultValue: 'us-east-1', description: 'AWS region')
    string(name: 'ECR_REPOSITORY_URL', defaultValue: '', description: 'Full ECR repository URL from terraform output')
    string(name: 'ANSIBLE_INSTANCE_ID', defaultValue: '', description: 'Ansible EC2 instance ID')
    booleanParam(name: 'RUN_SONAR', defaultValue: false, description: 'Run SonarCloud analysis (enable after Sonar setup)')
    booleanParam(name: 'DEPLOY', defaultValue: false, description: 'Trigger Ansible deploy to EKS (later phase)')
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

    stage('SonarCloud') {
      when {
        expression { return params.RUN_SONAR }
      }
      steps {
        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
          dir("${APP_DIR}") {
            sh '''
              mvn -B verify sonar:sonar \
                -Dsonar.projectKey=marisol-jenkins-kubernetes-cicd \
                -Dsonar.organization=${SONAR_ORG:-marisol-tembo} \
                -Dsonar.host.url=https://sonarcloud.io \
                -Dsonar.login=${SONAR_TOKEN}
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

    stage('Docker Build') {
      steps {
        sh '''
          docker build -t ${ECR_REPOSITORY_URL}:${IMAGE_TAG} -t ${ECR_REPOSITORY_URL}:latest ${APP_DIR}
        '''
      }
    }

    stage('Trivy Scan') {
      steps {
        sh '''
          trivy image --exit-code 1 --severity HIGH,CRITICAL ${ECR_REPOSITORY_URL}:${IMAGE_TAG}
        '''
      }
    }

    stage('Push to ECR') {
      steps {
        sh '''
          aws ecr get-login-password --region ${AWS_REGION} \
            | docker login --username AWS --password-stdin ${ECR_REPOSITORY_URL%/*}
          docker push ${ECR_REPOSITORY_URL}:${IMAGE_TAG}
          docker push ${ECR_REPOSITORY_URL}:latest
        '''
      }
    }

    stage('Deploy via Ansible') {
      when {
        expression { return params.DEPLOY }
      }
      steps {
        sh '''
          cat > /tmp/deploy-commands.json <<EOF
{
  "commands": [
    "set -euxo pipefail",
    "mkdir -p /opt/ansible && cd /opt/ansible",
    "if [ ! -d repo ]; then git clone https://github.com/marisol-tembo/marisol-jenkins-kubernetes-cicd.git repo; fi",
    "cd repo && git fetch --all && git reset --hard origin/main",
    "export IMAGE_TAG=${IMAGE_TAG}",
    "export ECR_REPOSITORY_URL=${ECR_REPOSITORY_URL}",
    "ansible-playbook ansible/deploy.yml -e image_tag=${IMAGE_TAG} -e ecr_repository_url=${ECR_REPOSITORY_URL}"
  ]
}
EOF

          COMMAND_ID=$(aws ssm send-command \
            --instance-ids "${ANSIBLE_INSTANCE_ID}" \
            --document-name "AWS-RunShellScript" \
            --comment "Deploy ${IMAGE_TAG} to EKS" \
            --parameters file:///tmp/deploy-commands.json \
            --query "Command.CommandId" \
            --output text)

          echo "SSM Command ID: ${COMMAND_ID}"

          aws ssm wait command-executed \
            --command-id "${COMMAND_ID}" \
            --instance-id "${ANSIBLE_INSTANCE_ID}"

          STATUS=$(aws ssm get-command-invocation \
            --command-id "${COMMAND_ID}" \
            --instance-id "${ANSIBLE_INSTANCE_ID}" \
            --query "Status" \
            --output text)

          echo "Ansible deploy status: ${STATUS}"
          test "${STATUS}" = "Success"
        '''
      }
    }
  }

  post {
    success {
      echo "Pipeline succeeded for image ${IMAGE_TAG}"
    }
    failure {
      echo "Pipeline failed. Use ansible/rollback.yml on the Ansible host if a bad release was deployed."
    }
  }
}
