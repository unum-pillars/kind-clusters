pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timeout(time: 90, unit: 'MINUTES')
    }

    stages {
        // One stage for each make command, so a red bubble is one act, in one Unum, and nothing else. The checks that need no cluster
        // come first, then the two Unums, brought up and proved. test-browser needs the permanent ingress cluster, and test-swap and
        // test-catalog are slow or need GitHub, so those are run by hand before a merge.
        stage('lint') {
            steps {
                sh 'make lint'
            }
        }
        stage('checks') {
            stages {
                stage('test-add') {
                    steps {
                        sh 'make test-add'
                    }
                }
                stage('test-version') {
                    steps {
                        sh 'make test-version'
                    }
                }
                stage('test-context') {
                    steps {
                        sh 'make test-context'
                    }
                }
                stage('test-stages') {
                    steps {
                        sh 'make test-stages'
                    }
                }
            }
        }
        stage('clusters') {
            // us and them as kind clusters on the agent, from the apps.yaml tags, and everything that proves them. Every call
            // names its cluster, so the two Unums come up at once, each lane doing down, up and test as stages of their own, and
            // the cross tests wait for both lanes
            environment {
                PATH = "${WORKSPACE}/bin:${PATH}"
            }
            stages {
                stage('tools') {
                    steps {
                        sh 'make tools'
                    }
                }
                stage('unums') {
                    parallel {
                        stage('us') {
                            stages {
                                stage('down') {
                                    steps {
                                        sh 'make down NAME=us'
                                    }
                                }
                                stage('up') {
                                    steps {
                                        sh 'make ci NAME=us'
                                    }
                                }
                                stage('test') {
                                    steps {
                                        sh 'make test NAME=us'
                                    }
                                }
                            }
                        }
                        stage('them') {
                            stages {
                                stage('down') {
                                    steps {
                                        sh 'make down NAME=them'
                                    }
                                }
                                stage('up') {
                                    steps {
                                        sh 'make ci NAME=them'
                                    }
                                }
                                stage('test') {
                                    steps {
                                        sh 'make test NAME=them'
                                    }
                                }
                            }
                        }
                    }
                }
                stage('test-cross') {
                    steps {
                        sh 'make test-cross'
                    }
                }
                stage('test-route') {
                    steps {
                        sh 'make test-route'
                    }
                }
            }
            post {
                always {
                    // The clusters are deleted, and the databases they leave in data/ are root's, which the next checkout could not clean
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
