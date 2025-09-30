import * as tl from "azure-pipelines-task-lib/task";
import { spawn } from "child_process";
import {
    logInfo,
    logError,
    getSystemAccessToken
} from "./agentSpecific";

function getSpCredsFromServiceConnection(scName: string) {
    const endpointId = tl.getInput(scName, true)!;
    const endpointAuth = tl.getEndpointAuthorization(endpointId, true);
    if (!endpointAuth) {
        throw new Error(`Unable to retrieve authorization object for service connection '${endpointId}'.`);
    }

    const params = endpointAuth.parameters || {};
    const allKeys = Object.keys(params);
    tl.debug(`Service connection auth scheme: ${endpointAuth.scheme}`);
    tl.debug(`Service connection available auth parameter keys: ${allKeys.join(", ")}`);

    // Azure RM (Service Principal secret) standard keys
    let clientId =
        params["serviceprincipalid"] ||
        params["principalId"] ||
        params["clientId"];

    let clientSecret =
        params["serviceprincipalkey"] ||
        params["clientSecret"];

    let tenantId =
        params["tenantid"] ||
        params["tenantId"];

    // Certificate-based SP (no client secret) – unsupported for now
    const certificate = params["servicePrincipalCertificate"] || params["certificate"];
    if (!clientSecret && certificate) {
        throw new Error("Certificate-based service connections currently not supported by this task. Use SP (secret) auth.");
    }

    if (!clientId || !clientSecret || !tenantId) {
        throw new Error(
            `Service connection missing one or more required parameters. Found keys: ${allKeys.join(", ")}. ` +
            "Expecting service principal (secret) connection with: serviceprincipalid, serviceprincipalkey, tenantid."
        );
    }

    return { clientId, clientSecret, tenantId };
}

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

        const scInputName = "azureServiceConnection";
        let spCreds: { clientId: string; clientSecret: string; tenantId: string } | undefined;

        try {
            spCreds = getSpCredsFromServiceConnection(scInputName);
            logInfo("Azure Service Connection credentials resolved.");
        } catch (e) {
            tl.setResult(tl.TaskResult.Failed, (e as Error).message);
            return;
        }

        // Append to args (DO NOT LOG secrets)
        args.push("-TenantId", spCreds.tenantId);
        args.push("-ClientId", spCreds.clientId);
        args.push("-ClientSecret", spCreds.clientSecret);

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
