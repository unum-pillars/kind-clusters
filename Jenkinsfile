pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
    }

    stages {
        // Checks that need no cluster only. The clusters themselves (make ci, test, test-cross, test-swap, test-catalog) are run by hand before a merge.
        stage('lint') {
            steps {
                sh 'make lint'
            }
        }
        stage('test') {
            steps {
                sh 'make test-add'
                sh 'make test-version'
            }
        }
        stage('tag') {
            // Only main, so other repos can use this version from its tag. make tag does nothing if the tag is already there
            when {
                branch 'main'
            }
            // A tag needs a committer, and Jenkins has none
            environment {
                GIT_COMMITTER_NAME = 'Leroy Jenkins'
                GIT_COMMITTER_EMAIL = 'leroy@jenkins.klot.io'
            }
            steps {
                withCredentials([usernamePassword(credentialsId: 'github', usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
                    // Jenkins checks out a detached commit, so the tag is the version file's
                    sh '''
                        git checkout -B main
                        git remote set-url origin "https://$GH_USER:$GH_TOKEN@${GIT_URL#https://}"
                        make tag
                    '''
                }
            }
        }
    }
}
