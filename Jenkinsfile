pipeline {
  agent any

  environment {
    AWS_REGION           = "${params.AWS_REGION}"
    ECR_REPOSITORY_NAME  = "${params.ECR_REPOSITORY_NAME}"
    IMAGE_TAG            = "${env.BUILD_NUMBER}"
    APP_DIR              = "app"
  }

  parameters {
    string(name: 'AWS_REGION', defaultValue: 'us-east-1', description: 'AWS region for ECR')
    string(name: 'ECR_REPOSITORY_NAME', defaultValue: 'jenkins-k8s-demo-app', description: 'ECR repository name (Terraform ecr_repository_name)')
    booleanParam(name: 'RUN_SONAR', defaultValue: true, description: 'Run SonarQube analysis on the Jenkins host')
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
          // Discover repo URI via instance role — no manual URL paste
          env.ECR_REPOSITORY_URL = sh(
            script: '''
              aws ecr describe-repositories \
                --repository-names "${ECR_REPOSITORY_NAME}" \
                --region "${AWS_REGION}" \
                --query 'repositories[0].repositoryUri' \
                --output text
            ''',
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
  }

  post {
    success {
      echo "Pipeline succeeded. Image: ${env.ECR_REPOSITORY_URL}:${IMAGE_TAG}"
    }
    failure {
      echo "Pipeline failed. Check Maven, SonarQube quality gate, Trivy, or ECR push."
    }
  }
}
