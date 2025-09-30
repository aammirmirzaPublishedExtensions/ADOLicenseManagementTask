import * as tl from "azure-pipelines-task-lib/task";
import { spawn } from "child_process";
import { logInfo, logError } from "./agentSpecific";

function getSpAuth(scInput: string) {
    const endpointId = tl.getInput(scInput, true)!;
    const auth = tl.getEndpointAuthorization(endpointId, true);
    if (!auth) {
        throw new Error(`No authorization object for service connection id '${endpointId}'.`);
    }
    const p = auth.parameters || {};
    const scheme = auth.scheme || "";
    const keys = Object.keys(p);
    tl.debug(`Auth scheme: ${scheme}`);
    tl.debug(`Auth param keys: ${keys.join(", ")}`);

    const clientId =
        p["serviceprincipalid"] ||
        p["principalId"] ||
        p["clientId"];

    const tenantId = p["tenantid"] || p["tenantId"];

    const clientSecret = p["serviceprincipalkey"] || p["clientSecret"]; // may be undefined (federated)
    const wifIssuer = p["workloadIdentityFederationIssuer"];
    const wifSubject = p["workloadIdentityFederationSubject"];

    return {
        clientId,
        tenantId,
        clientSecret,
        isFederated: !clientSecret && !!(wifIssuer || wifSubject),
        rawParams: keys
    };
}

export async function run() {
    try {
        const scName = "azureServiceConnection";
        const inactive = tl.getInput("inactiveDaysThreshold", true);
        const revoke = tl.getInput("Revoke", false);

        const auth = getSpAuth(scName);
        if (!auth.clientId || !auth.tenantId) {
            throw new Error(`Service connection missing clientId or tenantId. Keys present: ${auth.rawParams.join(", ")}`);
        }

        let exe = "pwsh";
        if (tl.getVariable("AGENT.OS") === "Windows_NT") {
            exe = "powershell.exe";
        }

        const scriptPath = `${__dirname}\\O365_Copilot_Optimization.ps1`;
        const args: string[] = [scriptPath, "-TenantId", auth.tenantId, "-ClientId", auth.clientId, "-inactiveDaysThreshold", inactive!];
        if (revoke) {
            args.push("-Revoke", revoke);
        }
        if (auth.clientSecret) {
            // Secret-based SP
            args.push("-ClientSecret", auth.clientSecret);
            logInfo("Using client secret auth (service principal).");
        } else if (auth.isFederated) {
            logInfo("Federated (workload identity) service connection detected (no secret). Expecting AZURE_FEDERATED_TOKEN.");
            // DO NOT fail yet; PowerShell will attempt federated flow using env AZURE_FEDERATED_TOKEN
        } else {
            throw new Error("Neither client secret nor federated parameters detected.");
        }

        logInfo(`Launching PowerShell (${exe})`);
        const child = spawn(exe, args, { windowsVerbatimArguments: true });

        child.stdout.on("data", d => process.stdout.write(d));
        child.stderr.on("data", d => process.stderr.write(d));

        child.on("close", code => {
            if (code !== 0) {
                tl.setResult(tl.TaskResult.Failed, `Script exited with code ${code}`);
            } else {
                tl.setResult(tl.TaskResult.Succeeded, "Completed");
            }
        });
    } catch (e) {
        const message = e instanceof Error ? e.message : String(e);
        logError(message);
        tl.setResult(tl.TaskResult.Failed, message);
    }
}
run();
