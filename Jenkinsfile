pipeline {
    agent any

    parameters {
        string(name: 'PACKAGE_NAME',     defaultValue: 'TestDeployPackage',     description: 'webMethods IS Package Name to deploy')
        string(name: 'TARGET_ENV',       defaultValue: 'DEV',  description: 'Target Environment: DEV | SIT | UAT | PROD')
        string(name: 'BRANCH_NAME',      defaultValue: 'main', description: 'Git branch to build from')
        booleanParam(name: 'SKIP_TESTS', defaultValue: false,  description: 'Skip unit tests')
        booleanParam(name: 'RELOAD_PKG', defaultValue: true,   description: 'Reload package after deployment')
    }

    environment {
        SAG_HOME        = 'C:\\SoftwareAG11'
        ABE_HOME        = "${SAG_HOME}\\common\\AssetBuildEnvironment"
        ABE_EXEC        = "${SAG_HOME}\\common\\lib\\ant\\bin\\ant.bat"
        JAVA_HOME       = "${SAG_HOME}\\jvm\\jvm"
        GIT_REPO_URL       = 'https://github.com/Jagadeesh999/TestDeployPackage'
        GIT_CREDENTIALS_ID = 'git-credentials'
        BUILD_DIR       = "${WORKSPACE}\\build"
        DIST_DIR        = "${WORKSPACE}\\dist"
        ABE_PROJECT_DIR = "${WORKSPACE}\\abe"
        COMPOSITE_FILE  = "${DIST_DIR}\\${params.PACKAGE_NAME}_${BUILD_NUMBER}.zip"
        ENV_CONFIG_FILE = "${WORKSPACE}\\config\\environments\\${params.TARGET_ENV}.properties"
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 45, unit: 'MINUTES')
        timestamps()
        disableConcurrentBuilds()
    }

    stages {

        stage('Validate Parameters') {
            steps {
                script {
                    if (!params.PACKAGE_NAME?.trim()) {
                        error("PACKAGE_NAME is required.")
                    }
                    def validEnvs = ['DEV', 'SIT', 'UAT', 'PROD']
                    if (!validEnvs.contains(params.TARGET_ENV)) {
                        error("TARGET_ENV must be one of: ${validEnvs.join(', ')}")
                    }
                    echo "Parameters validated - Package: ${params.PACKAGE_NAME}  Env: ${params.TARGET_ENV}"
                }
            }
        }

        stage('Checkout Source') {
            steps {
                cleanWs()
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: "*/${params.BRANCH_NAME}"]],
                    userRemoteConfigs: [[
                        url: "${GIT_REPO_URL}",
                        credentialsId: "${GIT_CREDENTIALS_ID}"
                    ]],
                    extensions: [[$class: 'CloneOption', depth: 1, shallow: true]]
                ])
                echo "Source checked out from branch: ${params.BRANCH_NAME}"
            }
        }

        stage('Load Environment Config') {
            steps {
                script {
                    if (!fileExists(ENV_CONFIG_FILE)) {
                        error("Environment config not found: ${ENV_CONFIG_FILE}")
                    }
                    // Parse .properties file manually - no plugin required
                    def propsText = readFile(file: ENV_CONFIG_FILE)
                    def props = [:]
                    propsText.readLines().each { line ->
                        line = line.trim()
                        if (line && !line.startsWith('#')) {
                            def parts = line.split('=', 2)
                            if (parts.length == 2) {
                                props[parts[0].trim()] = parts[1].trim()
                            }
                        }
                    }
                    env.IS_HOST           = props['is.host']
                    env.IS_PORT           = props['is.port']
                    env.IS_PROTOCOL       = props.containsKey('is.protocol') ? props['is.protocol'] : 'http'
                    env.IS_ADMIN_USER     = props.containsKey('is.admin.user') ? props['is.admin.user'] : 'Administrator'
                    env.IS_CREDENTIALS_ID = props['is.credentials.id']
                    echo "Loaded config for ${params.TARGET_ENV}: ${env.IS_HOST}:${env.IS_PORT}"
                }
            }
        }

        stage('ABE Build') {
            steps {
                script {
                    bat "if not exist \"${BUILD_DIR}\" mkdir \"${BUILD_DIR}\""
                    bat "if not exist \"${DIST_DIR}\" mkdir \"${DIST_DIR}\""
                    bat "PowerShell -ExecutionPolicy Bypass -File \"${WORKSPACE}\\scripts\\Prepare-ACD.ps1\" -PackageName ${params.PACKAGE_NAME} -WorkspaceDir \"${WORKSPACE}\" -AbeProjectDir \"${ABE_PROJECT_DIR}\""
                    bat """
                        set JAVA_HOME=${JAVA_HOME}
                        "${ABE_EXEC}" -f "${ABE_PROJECT_DIR}\\build.xml" ^
                            -Dproject.name=${params.PACKAGE_NAME} ^
                            -Dpackage.name=${params.PACKAGE_NAME} ^
                            -Dsrc.dir=${WORKSPACE}\\packages ^
                            -Dbuild.dir=${BUILD_DIR} ^
                            -Ddist.dir=${DIST_DIR} ^
                            -Dbuild.number=${BUILD_NUMBER} ^
                            build
                    """
                    if (!fileExists(COMPOSITE_FILE)) {
                        error("ABE composite file not created: ${COMPOSITE_FILE}")
                    }
                    echo "ABE build complete: ${COMPOSITE_FILE}"
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'build\\reports\\**\\*', allowEmptyArchive: true
                }
            }
        }

        stage('Run Unit Tests') {
            when {
                expression { !params.SKIP_TESTS }
            }
            steps {
                script {
                    bat "PowerShell -ExecutionPolicy Bypass -File \"${WORKSPACE}\\scripts\\Run-Tests.ps1\" -Host \"${env.IS_HOST}\" -Port \"${env.IS_PORT}\" -Package \"${params.PACKAGE_NAME}\" -ReportDir \"${BUILD_DIR}\\test-reports\""
                }
            }
            post {
                always {
                    junit allowEmptyResults: true,
                          testResults: 'build\\test-reports\\**\\*.xml'
                }
            }
        }

        stage('Backup Existing Package') {
            when {
                expression { params.TARGET_ENV != 'DEV' }
            }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: env.IS_CREDENTIALS_ID,
                    usernameVariable: 'IS_USER',
                    passwordVariable: 'IS_PASS'
                )]) {
                    bat "PowerShell -ExecutionPolicy Bypass -File \"${WORKSPACE}\\scripts\\Backup-Package.ps1\" -Host \"${env.IS_HOST}\" -Port \"${env.IS_PORT}\" -Protocol \"${env.IS_PROTOCOL}\" -User \"${IS_USER}\" -Password \"${IS_PASS}\" -Package \"${params.PACKAGE_NAME}\" -BackupDir \"${DIST_DIR}\\backups\""
                }
                echo "Package backed up"
            }
        }

        stage('Deploy Package') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: env.IS_CREDENTIALS_ID,
                    usernameVariable: 'IS_USER',
                    passwordVariable: 'IS_PASS'
                )]) {
                    bat "PowerShell -ExecutionPolicy Bypass -File \"${WORKSPACE}\\scripts\\Deploy-Package.ps1\" -Host \"${env.IS_HOST}\" -Port \"${env.IS_PORT}\" -Protocol \"${env.IS_PROTOCOL}\" -User \"${IS_USER}\" -Password \"${IS_PASS}\" -Package \"${params.PACKAGE_NAME}\" -CompositeFile \"${COMPOSITE_FILE}\" -Reload ${params.RELOAD_PKG}"
                }
                echo "Package deployed to ${params.TARGET_ENV}"
            }
        }

        stage('Post-Deployment Health Check') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: env.IS_CREDENTIALS_ID,
                    usernameVariable: 'IS_USER',
                    passwordVariable: 'IS_PASS'
                )]) {
                    bat "PowerShell -ExecutionPolicy Bypass -File \"${WORKSPACE}\\scripts\\Health-Check.ps1\" -Host \"${env.IS_HOST}\" -Port \"${env.IS_PORT}\" -Protocol \"${env.IS_PROTOCOL}\" -User \"${IS_USER}\" -Password \"${IS_PASS}\" -Package \"${params.PACKAGE_NAME}\""
                }
                echo "Health check passed"
            }
        }
    }

    post {
        success {
            echo "Pipeline complete! Package: ${params.PACKAGE_NAME} deployed to ${params.TARGET_ENV}"
            archiveArtifacts artifacts: "dist\\*.zip", allowEmptyArchive: true
        }
        failure {
            echo "Pipeline failed. Review logs above."
            script {
                if (params.TARGET_ENV != 'DEV') {
                    echo "Run rollback if needed: scripts\\Rollback-Package.ps1"
                }
            }
        }
        always {
            cleanWs(cleanWhenNotBuilt: false,
                    deleteDirs: true,
                    disableDeferredWipeout: true,
                    notFailBuild: true,
                    patterns: [[pattern: 'dist/**', type: 'EXCLUDE']])
        }
    }
}