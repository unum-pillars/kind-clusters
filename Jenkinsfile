pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
    }

    stages {
        // Offline checks only. The clusters themselves (make ci, test, test-cross) are run by hand before a merge.
        stage('lint') {
            steps {
                sh 'make lint'
            }
        }
    }
}
