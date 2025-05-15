import tl = require("azure-pipelines-task-lib/task");
import { basename } from "path";

import {
    logInfo,
    logError,
    getSystemAccessToken
}  from "./agentSpecific";

export async function run() {
    try {

        // Get the build and release details
        let Organizations = tl.getInput("Organizations");
        let NumberOfMonths = tl.getInput("NumberOfMonths");
        let usersExcludedFromLicenseChange = tl.getInput("usersExcludedFromLicenseChange");
        let AccessToken = tl.getInput("AccessToken");

        // let teamproject = process.env.SYSTEM_TEAMPROJECT;
        // let releaseid = process.env.RELEASE_RELEASEID;
        // let buildid = process.env.BUILD_BUILDID;

        // we need to get the verbose flag passed in as script flag
        var verbose = (tl.getVariable("System.Debug") === "true");
// Generates automatic token for the running
        // let url = tl.getEndpointUrl("SYSTEMVSSCONNECTION", false);
        // let token = tl.getEndpointAuthorizationParameter("SYSTEMVSSCONNECTION", "ACCESSTOKEN", false);

        // find the executeable
        let executable = "pwsh";
        if (tl.getVariable("AGENT.OS") === "Windows_NT") {
            if (!tl.getBoolInput("usePSCore")) {
                executable = "powershell.exe";
            }
            logInfo(`Using executable '${executable}'`);
        } else {
            logInfo(`Using executable '${executable}' as only option on '${tl.getVariable("AGENT.OS")}'`);
        }

        // we need to NOT pass the null param
        // PS args ScriptArguments: '-Method "POST" -ClientToken $(akamai-luna-clienttoken-2) -ClientAccessToken $(akamai-luna-clientaccess-2)
        // -ClientSecret $(akamai-luna-clientsecret-2) -hostAddress $(hostAddress) -Action invalidate -URLs $(URL)'
        // var args = [__dirname + "\\AkamaiFastPurgeTask.ps1",
        var args = [__dirname + "\\ADOLicenseManagement.ps1"
                // "-AccessToken", token
                // "-Method", Method,
                // "-ClientToken", ClientToken,
                // "-ClientAccessToken", ClientAccessToken,
                // "-ClientSecret", ClientSecret,
                // "-hostAddress", hostAddress,
                // "-Action", Action,
                // "-URLs", URLs,
                // "-Tags", Tags,
                // "-Network", Network
        ];

        if (Organizations) {
            args.push("-Organizations");
            args.push(Organizations);
        }

        if (NumberOfMonths) {
            args.push("-NumberOfMonths");
            args.push(NumberOfMonths);
        }

        if (AccessToken) {
            args.push("-AccessToken");
            args.push(AccessToken);
        }

        if (usersExcludedFromLicenseChange) {
            args.push("-usersExcludedFromLicenseChange");
            args.push(usersExcludedFromLicenseChange);
        }

        if (verbose) {
            args.push("-Verbose");
        }

        logInfo(`${executable} ${args.join(" ")}`);

        var spawn = require("child_process").spawn, child;
        child = spawn(executable, args);
        child.stdout.on("data", function (data) {
            logInfo(data.toString());
        });
        child.stderr.on("data", function (data) {
            logError(data.toString());
        });
        child.on("exit", function () {
            logInfo("Script finished");
        });
    }
    catch (err) {
        logError(err);
    }
}

run();
