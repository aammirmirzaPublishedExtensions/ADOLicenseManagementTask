import * as tl from "azure-pipelines-task-lib/task";
import { logInfo, logError } from "./agentSpecific";
import { spawn } from "child_process";

export async function run() {
    try {
        // Get the build and release details
        const Organizations = tl.getInput("Organizations");
        const NumberOfMonths = tl.getInput("NumberOfMonths");
        const usersExcludedFromLicenseChange = tl.getInput("usersExcludedFromLicenseChange");
        const AccessToken = tl.getInput("AccessToken");
        const emailNotify = tl.getInput("emailNotify");
        const smtpUserName = tl.getInput("SMTP_UserName");
        const smtpPassword = tl.getInput("SMTP_Password");
        const sentFrom = tl.getInput("sentFrom");
        const adiitionalComment = tl.getInput("adiitionalComment");

        const verbose = (tl.getVariable("System.Debug") === "true");

        let executable = "pwsh";
        if (tl.getVariable("AGENT.OS") === "Windows_NT") {
            if (!tl.getBoolInput("usePSCore")) {
                executable = "powershell.exe";
            }
            logInfo(`Using executable '${executable}'`);
        } else {
            logInfo(`Using executable '${executable}' as only option on '${tl.getVariable("AGENT.OS")}'`);
        }

        const args = [__dirname + "\\ADOLicenseManagement.ps1"];

        if (Organizations) {
            args.push("-Organizations", Organizations);
        }
        if (NumberOfMonths) {
            args.push("-NumberOfMonths", NumberOfMonths);
        }
        if (AccessToken) {
            args.push("-AccessToken", AccessToken);
        }
        if (usersExcludedFromLicenseChange) {
            args.push("-usersExcludedFromLicenseChange", usersExcludedFromLicenseChange);
        }
        if (emailNotify) {
            args.push("-emailNotify", emailNotify);
        }
        if (smtpUserName) {
            args.push("-SMTP_UserName", smtpUserName);
        }
        if (smtpPassword) {
            args.push("-SMTP_Password", smtpPassword);
        }
        if (sentFrom) {
            args.push("-sentFrom", sentFrom);
        }
        if (adiitionalComment) {
            args.push("-adiitionalComment", adiitionalComment);
        }
        if (verbose) {
            args.push("-Verbose");
        }

        logInfo(`${executable} ${args.join(" ")}`);

        const child = spawn(executable, args);
        child.stdout.on("data", (data) => logInfo(data.toString()));
        child.stderr.on("data", (data) => logError(data.toString()));
        child.on("exit", () => logInfo("Script finished"));
    } catch (err) {
        logError(err);
    }
}

run();