pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timeout(time: 90, unit: 'MINUTES')
        // The checkout is a stage of its own, after the clean, so what an earlier run left behind can't stop it
        skipDefaultCheckout(true)
    }

    stages {
        // One step for each make command, in stages grouped by function, so a red row is one command, in one stage, in one Unum.
        // Clone, then everything within the repo that needs no cluster, then the two Unums, brought up and proved, and across them. test-browser needs the
        // permanent ingress cluster, and test-swap and test-catalog are slow or need GitHub, so those are run by hand before a merge.
        stage('clone') {
            // The clusters' databases in data/ are root's, and a run that was stopped before its cleanup leaves them, which the
            // checkout's git clean can't remove. So data/ is removed before the checkout, whatever happened last time
            steps {
                sh 'docker run --rm -v "$PWD:/workspace" busybox:1.36 sh -c "rm -rf /workspace/data"'
                checkout scm
            }
        }
        stage('within') {
            steps {
                sh 'make lint'
                sh 'make test-add'
                sh 'make test-version'
                sh 'make test-context'
                sh 'make test-stages'
                sh 'make tools'
            }
        }
        stage('clusters') {
            // us and them as kind clusters on the agent, from the apps.yaml tags, and everything that proves them. Every call
            // names its cluster, so the two Unums come up at once, each lane doing down, up and test, and the cross tests wait
            // for both lanes
            environment {
                PATH = "${WORKSPACE}/bin:${PATH}"
            }
            stages {
                stage('unums') {
                    parallel {
                        stage('us') {
                            steps {
                                sh 'make down NAME=us'
                                sh 'make ci NAME=us'
                                sh 'make test NAME=us'
                                sh 'make test-certificates NAME=us'
                            }
                        }
                        stage('them') {
                            steps {
                                sh 'make down NAME=them'
                                sh 'make ci NAME=them'
                                sh 'make test NAME=them'
                                sh 'make test-certificates NAME=them'
                            }
                        }
                    }
                }
                stage('across') {
                    steps {
                        sh 'make test-cross'
                        sh 'make test-route'
                        sh 'make test-write'
                    }
                }
            }
            post {
                always {
                    // The clusters are deleted, and the databases they leave in data/ are root's, which the next clean removes if this can't
                    sh 'make down NAME=us; make down NAME=them; docker run --rm -v "$PWD/data:/data" busybox:1.36 sh -c "rm -rf /data/*"; true'
                }
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
                    // Jenkins checks out a detached commit, so the tag is the version file's. The URL comes from git, since checkout scm
                    // as a step doesn't put it in the environment
                    sh '''
                        git checkout -B main
                        git remote set-url origin "https://$GH_USER:$GH_TOKEN@$(git remote get-url origin | sed 's|^https://||')"
                        make tag
                    '''
                }
            }
        }
    }
}
