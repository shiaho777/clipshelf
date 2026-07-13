import ServiceManagement

protocol LaunchAtLoginService {
    func setEnabled(_ enabled: Bool) throws
}

final class SMAppLaunchAtLoginService: LaunchAtLoginService {
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
