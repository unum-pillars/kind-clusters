pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
    }

    stages {
        // Offline checks only. The clusters themselves (make ci, test, test-cross, test-swap, test-catalog) are run by hand before a merge.
        stage('lint') {
            steps {
                sh 'make lint'
            }
        }
        stage('test') {
            steps {
                sh 'make test-add'
            }
        }
    }
}
