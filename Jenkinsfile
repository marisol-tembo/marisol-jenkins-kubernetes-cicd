pipeline {
  agent any

  environment {
    APP_DIR = "app"
  }

  parameters {
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
  }

  post {
    success {
      echo "Pipeline succeeded (Checkout + Maven Test + SonarQube)"
    }
    failure {
      echo "Pipeline failed. Check Maven tests or SonarQube quality gate."
    }
  }
}
