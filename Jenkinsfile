pipeline {
    agent any

    parameters {
        string(name: 'PACKAGE_NAME',     defaultValue: 'TestDeployPackage', description: 'webMethods IS Package Name to deploy')
        string(name: 'TARGET_ENV',       defaultValue: 'DEV',               description: 'Target Environment: DEV | SIT | UAT | PROD')
        string(name: 'BRANCH_NAME',      defaultValue: 'main',              description: 'Git branch to build from')
        booleanParam(name: 'SKIP_TESTS', defaultValue: false,               description: 'Skip unit tests')
        booleanParam(name: 'RELOAD_PKG', defaultValue: true,                description: 'Reload package after deployment')
    }

    environment {
        // -- SAG 11.x Paths (Windows - forward slashes for ABE, backslashes for bat) --
        SAG_HOME         = 'C:\\SoftwareAG11'
        SAG_HOME_FWD     = 'C:/SoftwareAG11'
        ABE_HOME         = 'C:\\SoftwareAG11\\common\\AssetBuildEnvironment'
        ABE_BUILD_BAT    = 'C:\\SoftwareAG11\\common\\AssetBuildEnvironment\\bin\\build.bat'
        IS_CONFIG_DIR    = 'C:/SoftwareAG11/IntegrationServer/instances/default/config'

        // -- Repository --
        GIT_REPO_URL       = 'https://github.com/Jagadeesh999/TestDeployPackage'
        GIT_CREDENTIALS_ID = 'git-credentials'

        // -- Build Paths --
        BUILD_DIR      = "${WORKSPACE}\\build"
        DIST_DIR       = "${WORKSPACE}\\dist"
        PACKAGES_DIR   = "${WORKSPACE}\\packages"

        // -- Environment Config --
        ENV_CONFIG_FILE = "${WORKSPACE}\\config\\environments\\${params.TARGET_ENV}.properties"
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 45, unit: 'MINUTES')
        timestamps()
        disableConcurrentBuilds()
    }

    stages {

        // -- 1. VALIDATE --
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

        // -- 2. CHECKOUT --
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

        // -- 3. LOAD ENV CONFIG --
        stage('Load Environment Config') {
            steps {
                script {
                    if (!fileExists(ENV_CONFIG_FILE)) {
                        error("Environment config not found: ${ENV_CONFIG_FILE}")
                    }
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
                    env.IS_PROTOCOL       = props.containsKey('is.protocol')   ? props['is.protocol']   : 'http'
                    env.IS_ADMIN_USER     = props.containsKey('is.admin.user') ? props['is.admin.user'] : 'Administrator'
                    env.IS_CREDENTIALS_ID = props['is.credentials.id']
                    echo "Loaded config for ${params.TARGET_ENV}: ${env.IS_HOST}:${env.IS_PORT}"
                }
            }
        }

        // -- 4. ABE BUILD (SAG 11.x) --
        stage('ABE Build') {
            steps {
                script {
                    // Create output directories
                    bat "if not exist \"${BUILD_DIR}\" mkdir \"${BUILD_DIR}\""
                    bat "if not exist \"${DIST_DIR}\" mkdir \"${DIST_DIR}\""

                    // Forward-slash versions required by ABE build.properties
                    def workspaceFwd  = WORKSPACE.replace('\\', '/')
                    def distDirFwd    = "${workspaceFwd}/dist"
                    def packagesDirFwd = "${workspaceFwd}/packages"

                    // Write a runtime build.properties by reading the template and substituting values
                    def template = readFile("${WORKSPACE}\\abe\\build.properties.template")
                    def buildProps = template
                        .replace('build.output.dir=',       "build.output.dir=${distDirFwd}")
                        .replace('build.source.dir=',       "build.source.dir=${packagesDirFwd}")
                        .replace('build.source.project.dir=', "build.source.project.dir=${packagesDirFwd}")
                        .replace('build.version=1.0',       "build.version=${BUILD_NUMBER}")
                        .replace('is.acdl.config.dir=',     "is.acdl.config.dir=${IS_CONFIG_DIR}")

                    // Write build.properties into workspace root (build.bat expects it in CWD)
                    writeFile file: "${WORKSPACE}\\build.properties", text: buildProps
                    echo "build.properties written to workspace root"

                    // Run ABE build.bat from workspace root
                    bat """
                        cd /d "${WORKSPACE}"
                        "${ABE_BUILD_BAT}"
                    """

                    // Find the generated composite ZIP in dist output
                    def distFiles = findFiles(glob: "dist/**/${params.PACKAGE_NAME}*.zip")
                    if (!distFiles || distFiles.length == 0) {
                        distFiles = findFiles(glob: "dist/**/*.zip")
                    }
                    if (!distFiles || distFiles.length == 0) {
                        error("ABE build completed but no composite ZIP found under dist/")
                    }
                    env.COMPOSITE_FILE = "${WORKSPACE}\\${distFiles[0].path}"
                    echo "ABE build complete. Composite: ${env.COMPOSITE_FILE}"
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'dist/**/*.zip', allowEmptyArchive: true
                }
            }
        }

        // -- 5. UNIT TESTS --
        // stage('Run Unit Tests') {
        //     when {
        //         expression { !params.SKIP_TESTS }
        //     }
        //     steps {
        //         withCredentials([usernamePassword(
        //             credentialsId: env.IS_CREDENTIALS_ID,
        //             usernameVariable: 'IS_USER',
        //             passwordVariable: 'IS_PASS'
        //         )]) {
        //             bat "PowerShell -ExecutionPolicy Bypass -File \"${WORKSPACE}\\scripts\\Run-Tests.ps1\" -ISHost \"${env.IS_HOST}\" -Port \"${env.IS_PORT}\" -User \"${IS_USER}\" -Password \"${IS_PASS}\" -Package \"${params.PACKAGE_NAME}\" -ReportDir \"${BUILD_DIR}\\test-reports\""
        //         }
        //     }
        //     post {
        //         always {
        //             junit allowEmptyResults: true,
        //                   testResults: 'build\\test-reports\\**\\*.xml'
        //         }
        //     }
        // }

        // -- 6. BACKUP (non-DEV) --
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
                    bat "PowerShell -ExecutionPolicy Bypass -File \"${WORKSPACE}\\scripts\\Backup-Package.ps1\" -ISHost \"${env.IS_HOST}\" -Port \"${env.IS_PORT}\" -Protocol \"${env.IS_PROTOCOL}\" -User \"${IS_USER}\" -Password \"${IS_PASS}\" -Package \"${params.PACKAGE_NAME}\" -BackupDir \"${DIST_DIR}\\backups\""
                }
                echo "Package backed up"
            }
        }

        // -- 7. DEPLOY --
        stage('Deploy Package') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: env.IS_CREDENTIALS_ID,
                    usernameVariable: 'IS_USER',
                    passwordVariable: 'IS_PASS'
                )]) {
                    bat "PowerShell -ExecutionPolicy Bypass -File \"${WORKSPACE}\\scripts\\Deploy-Package.ps1\" -ISHost \"${env.IS_HOST}\" -Port \"${env.IS_PORT}\" -Protocol \"${env.IS_PROTOCOL}\" -User \"${IS_USER}\" -Password \"${IS_PASS}\" -Package \"${params.PACKAGE_NAME}\" -CompositeFile \"${env.COMPOSITE_FILE}\" -Reload ${params.RELOAD_PKG}"
                }
                echo "Package deployed to ${params.TARGET_ENV}"
            }
        }

        // -- 8. HEALTH CHECK --
        stage('Post-Deployment Health Check') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: env.IS_CREDENTIALS_ID,
                    usernameVariable: 'IS_USER',
                    passwordVariable: 'IS_PASS'
                )]) {
                    bat "PowerShell -ExecutionPolicy Bypass -File \"${WORKSPACE}\\scripts\\Health-Check.ps1\" -ISHost \"${env.IS_HOST}\" -Port \"${env.IS_PORT}\" -Protocol \"${env.IS_PROTOCOL}\" -User \"${IS_USER}\" -Password \"${IS_PASS}\" -Package \"${params.PACKAGE_NAME}\""
                }
                echo "Health check passed"
            }
        }
    }

    post {
        success {
            echo "Pipeline complete! Package: ${params.PACKAGE_NAME} deployed to ${params.TARGET_ENV}"
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