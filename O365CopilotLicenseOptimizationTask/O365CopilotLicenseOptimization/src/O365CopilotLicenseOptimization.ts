import * as tl from "azure-pipelines-task-lib/task";
import { spawn } from "child_process";
import {
    logInfo,
    logError,
    getSystemAccessToken
} from "./agentSpecific";
export async function run() {
    try {
        // Get the build and release details
        let inactiveDaysThreshold = tl.getInput("inactiveDaysThreshold");
        let Revoke = tl.getInput("Revoke");
        const azureServiceConnection = tl.getInput("azureServiceConnection", false);

        let executable = "pwsh";
        if (tl.getVariable("AGENT.OS") === "Windows_NT" && !tl.getBoolInput("usePSCore")) {
            executable = "powershell.exe";
        }
        logInfo(`Using executable '${executable}'`);

        // Base args (script path)
        const scriptPath = __dirname + "\\O365_Copilot_Optimization.ps1";
        let args: string[] = [ scriptPath ];

        if (inactiveDaysThreshold) {
            args.push("-inactiveDaysThreshold", inactiveDaysThreshold);
        }
        if (Revoke) {
            args.push("-Revoke", Revoke);
        }

        if (azureServiceConnection) {
            logInfo("Azure Service Connection provided. Extracting SP credentials.");
            const auth = tl.getEndpointAuthorization(azureServiceConnection, false);
            if (!auth) {
                throw new Error("Failed to retrieve service connection authorization.");
            }
            const clientId = auth.parameters["serviceprincipalid"];
            const clientSecret = auth.parameters["serviceprincipalkey"];
            const tenantId = auth.parameters["tenantid"];
            if (!clientId || !clientSecret || !tenantId) {
                throw new Error("Service connection missing one of: serviceprincipalid / serviceprincipalkey / tenantid.");
            }
            // Pass silently (avoid logging secrets)
            args.push("-TenantId", tenantId);
            args.push("-ClientId", clientId);
            args.push("-ClientSecret", clientSecret);
        } else {
            logInfo("No Azure Service Connection supplied. Script will attempt legacy Az context token acquisition.");
        }

        logInfo(`Invoking script with ${args.length - 1} arguments (secrets not logged).`);
        const child = spawn(executable, args, { windowsVerbatimArguments: true });
        child.stdout.on("data", (data) => logInfo(data.toString()));
        child.stderr.on("data", (data) => logError(data.toString()));
        child.on("exit", () => logInfo("Script finished"));
    } catch (err) {
        logError(err);
    }
}
run();
