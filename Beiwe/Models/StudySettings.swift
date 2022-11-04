import Foundation
import ObjectMapper

/* Example JSON:  (uuseful but this is quite old, there are new keys.  you get the idea tho.)
 { client_public_key: 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAn4ynh9zr7TZJBDoWx9TB78Mo7mAL4hSoLPEEGoZdEffvpKcXmY6qZOzXU6CzODts/3XXbqFHQrPKY9EnaumifeKpzIJZDRf6jUZD5SOFACLTH6u6+/2KiZKaGJ591GJTH4r/1LxvvIEAr2XxK9qx49RKlBl3dGPYn+7079wzV9mhdrYbqLgJCgZr0TqSiJvVYbGDuESnPZ5/1doAaFWnL8JILHv/Hf6HBTroePZmEsu00r2PQiEURtUWt76auccwKPzG+I6wqKfFR4o4uUovAZjxUledpvucXwOi10jCVK70MEVUTGKYp6/m2LyEdtGrKImMja/sAuoMU9qlaNPsaQIDAQAB',
 device_settings:
 { about_page_text: 'The Beiwe application runs on your phone and helps researchers ...',
 accelerometer: true,
 accelerometer_off_duration_seconds: 300,
 accelerometer_on_duration_seconds: 300,
 bluetooth: true,
 bluetooth_global_offset_seconds: 150,
 bluetooth_on_duration_seconds: 300,
 bluetooth_total_duration_seconds: 0,
 call_clinician_button_text: 'Call My Clinician',
 calls: true,
 check_for_new_surveys_frequency_seconds: 21600,
 consent_form_text: ' I have read and understood ....',
 create_new_data_files_frequency_seconds: 900,
 gps: true,
 gps_off_duration_seconds: 300,
 gps_on_duration_seconds: 300,
 power_state: true,
 seconds_before_auto_logout: 300,
 survey_submit_success_toast_text: 'Thank you for completing the survey....',
 texts: true,
 upload_data_files_frequency_seconds: 3600,
 voice_recording_max_time_length_seconds: 300,
 wifi: true,
 wifi_log_frequency_seconds: 300 } } */

struct ConsentSection: Mappable {
    init?(map: Map) {}
    
    var text: String = ""
    var more: String = ""

    // Mappable
    mutating func mapping(map: Map) {
        text <- map["text"]
        more <- map["more"]
    }
}

struct StudySettings: Mappable {
    init?(map: Map) {}

    // Disabled non-ios keys (data streams) htat we don't need to import
    // var bluetooth = false
    // var bluetoothOnDurationSeconds = 0
    // var bluetoothTotalDurationSeconds = 0
    // var bluetoothGlobalOffsetSeconds = 0
    // var calls = false
    // var texts = false

    // DEFAULT VALUES for parameters received from the server at registration
    
    // Participant detail
    var clientPublicKey: String?

    // Study settings
    var checkForNewSurveysFreqSeconds = 21600
    var createNewDataFileFrequencySeconds = 900
    var secondsBeforeAutoLogout = 300
    var uploadDataFileFrequencySeconds = 3600
    var voiceRecordingMaxLengthSeconds = 300
    var uploadOverCellular = false
    var callClinicianButtonEnabled = true
    var callResearchAssistantButtonEnabled = true

    // text strings
    var aboutPageText = ""
    var callClinicianText = "Call My Clinician"
    var consentFormText = "I have read and understood the information about the study and all of my questions about the study have been answered by the study researchers."
    var submitSurveySuccessText = "Thank you for completing the survey.  A clinician will not see your answers immediately, so if you need help or are thinking about harming yourself, please contact your clinician.  You can also press the \"Call My Clinician\" button."
    var consentSections: [String: ConsentSection] = [:]  // this is an encoded json list of strings. (why?)

    // DATA STREAMS
    // Accelerometer
    var accelerometer = false
    var accelerometerOffDurationSeconds = 300
    var accelerometerOnDurationSeconds = 0
    var accelerometerFrequency = 10
    // GPS data
    var gps = false
    var gpsOffDurationSeconds = 300
    var gpsOnDurationSeconds = 0
    var fuzzGps = false
    // Powerstate logging
    var powerState = false
    // wifi scans
    var wifi = false
    var wifiLogFrequencySeconds = 300
    // Proximity
    var proximity = false
    // Magnetometer
    var magnetometer = false
    var magnetometerOffDurationSeconds = 300
    var magnetometerOnDurationSeconds = 0
    // gyroscope
    var gyro = false
    var gyroOffDurationSeconds = 300
    var gyroOnDurationSeconds = 0
    var gyroFrequency = 10
    // Device motion
    var motion = false
    var motionOffDurationSeconds = 300
    var motionOnDurationSeconds = 0
    // Reachability
    var reachability = false

    // firebase/gcm stuff (most of this is junk we don't use)
    var gcmSenderID = ""
    var isGcmEnabled = true
    var googleAppID = ""
    var clientID = ""
    var reversedClientID = ""
    var apiKey = ""
    var plistVersion = 1
    var bundleID = ""
    var projectID = ""
    var storageBucket = ""
    var isAdsEnabled = false
    var isAnalyticsEnabled = false
    var isAppInviteEnabled = true
    var isSignInEnabled = true
    var databaseURL = ""

    // Mappable
    mutating func mapping(map: Map) {
        // This appears to be the location where we define how to read various data sources, the study settings and the firebase creds.
        clientPublicKey                     <- map["client_public_key"]
        aboutPageText                       <- map["device_settings.about_page_text"]
        accelerometer                       <- map["device_settings.accelerometer"]
        accelerometerOffDurationSeconds     <- map["device_settings.accelerometer_off_duration_seconds"]
        accelerometerOnDurationSeconds      <- map["device_settings.accelerometer_on_duration_seconds"]
        accelerometerFrequency              <- map["device_settings.accelerometer_frequency"]
        // bluetooth                           <- map["device_settings.bluetooth"]
        // bluetoothGlobalOffsetSeconds        <- map["device_settings.bluetooth_global_offset_seconds"]
        // bluetoothOnDurationSeconds          <- map["device_settings.bluetooth_on_duration_seconds"]
        // bluetoothTotalDurationSeconds       <- map["device_settings.bluetooth_total_duration_seconds"]
        callClinicianText                   <- map["device_settings.call_clinician_button_text"]
        // calls                               <- map["device_settings.calls"]
        checkForNewSurveysFreqSeconds       <- map["device_settings.check_for_new_surveys_frequency_seconds"]
        consentFormText                     <- map["device_settings.consent_form_text"]
        createNewDataFileFrequencySeconds   <- map["device_settings.create_new_data_files_frequency_seconds"]
        gps                                 <- map["device_settings.gps"]
        gpsOffDurationSeconds               <- map["device_settings.gps_off_duration_seconds"]
        gpsOnDurationSeconds                <- map["device_settings.gps_on_duration_seconds"]
        powerState                          <- map["device_settings.power_state"]
        secondsBeforeAutoLogout             <- map["device_settings.seconds_before_auto_logout"]
        submitSurveySuccessText             <- map["device_settings.survey_submit_success_toast_text"]
        // texts                               <- map["device_settings.texts"]
        uploadDataFileFrequencySeconds      <- map["device_settings.upload_data_files_frequency_seconds"]
        voiceRecordingMaxLengthSeconds      <- map["device_settings.voice_recording_max_time_length_seconds"]
        wifi                                <- map["device_settings.wifi"]
        wifiLogFrequencySeconds             <- map["device_settings.wifi_log_frequency_seconds"]
        proximity                           <- map["device_settings.proximity"]
        magnetometer                        <- map["device_settings.magnetometer"]
        magnetometerOffDurationSeconds      <- map["device_settings.magnetometer_off_duration_seconds"]
        magnetometerOnDurationSeconds       <- map["device_settings.magnetometer_on_duration_seconds"]
        gyro                                <- map["device_settings.gyro"]
        gyroOffDurationSeconds              <- map["device_settings.gyro_off_duration_seconds"]
        gyroOnDurationSeconds               <- map["device_settings.gyro_on_duration_seconds"]
        gyroFrequency                       <- map["device_settings.gyro_frequency"]
        motion                              <- map["device_settings.devicemotion"]
        motionOffDurationSeconds            <- map["device_settings.devicemotion_off_duration_seconds"]
        motionOnDurationSeconds             <- map["device_settings.devicemotion_on_duration_seconds"]
        reachability                        <- map["device_settings.reachability"]
        consentSections                     <- map["device_settings.consent_sections"]
        uploadOverCellular                  <- map["device_settings.allow_upload_over_cellular_data"]
        fuzzGps                             <- map["device_settings.use_gps_fuzzing"]
        callClinicianButtonEnabled          <- map["device_settings.call_clinician_button_enabled"]
        callResearchAssistantButtonEnabled  <- map["device_settings.call_research_assistant_button_enabled"]
        // firebase details
        clientID                            <- map["ios_plist.CLIENT_ID"]
        reversedClientID                    <- map["ios_plist.REVERSED_CLIENT_ID"]
        apiKey                              <- map["ios_plist.API_KEY"]
        gcmSenderID                         <- map["ios_plist.GCM_SENDER_ID"]
        plistVersion                        <- map["ios_plist.PLIST_VERSION"]
        bundleID                            <- map["ios_plist.BUNDLE_ID"]
        projectID                           <- map["ios_plist.PROJECT_ID"]
        storageBucket                       <- map["ios_plist.STORAGE_BUCKET"]
        isAdsEnabled                        <- map["ios_plist.IS_ADS_ENABLED"]
        isAnalyticsEnabled                  <- map["ios_plist.IS_ANALYTICS_ENABLED"]
        isAppInviteEnabled                  <- map["ios_plist.IS_APPINVITE_ENABLED"]
        isGcmEnabled                        <- map["ios_plist.IS_GCM_ENABLED"]
        isSignInEnabled                     <- map["ios_plist.IS_SIGNIN_ENABLED"]
        googleAppID                         <- map["ios_plist.GOOGLE_APP_ID"]
        databaseURL                         <- map["ios_plist.DATABASE_URL"]
    }
    
}
