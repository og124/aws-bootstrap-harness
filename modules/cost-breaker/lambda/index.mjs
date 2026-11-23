// Cost circuit breaker — disables a CloudFront distribution when an alarm or
// the budget fires. Deployed by modules/cost-breaker; uses the AWS SDK v3
// bundled with the Lambda Node.js runtime.
//
// Restore service after investigating:
//   aws lambda invoke --region us-east-1 --function-name <name>-breaker \
//     --cli-binary-format raw-in-base64-out --payload '{"action":"enable"}' /dev/stdout
import {
  CloudFrontClient,
  GetDistributionConfigCommand,
  UpdateDistributionCommand,
} from "@aws-sdk/client-cloudfront";
import { SNSClient, PublishCommand } from "@aws-sdk/client-sns";

// Pull whatever human-readable cause we can out of the SNS payload.
const describeTrigger = (event) => {
  const records = event?.Records || [];
  if (records.length === 0) return "direct invoke";

  return records
    .map((r) => {
      const raw = r.Sns?.Message || "";
      try {
        const m = JSON.parse(raw);
        if (m.AlarmName) return `alarm ${m.AlarmName}: ${m.NewStateReason || m.NewStateValue}`;
        if (m.budgetName) return `budget ${m.budgetName} breached`;
      } catch {
        /* not JSON — Budgets sends plain text */
      }
      return (r.Sns?.Subject ? r.Sns.Subject + " — " : "") + raw.slice(0, 500);
    })
    .join("\n");
};

/**
 * @param {object} deps
 * @param {(id: string) => Promise<{ETag: string, DistributionConfig: object}>} deps.getConfig
 * @param {(id: string, etag: string, config: object) => Promise<void>} deps.updateConfig
 * @param {(subject: string, message: string) => Promise<void>} deps.notify
 * @param {string} deps.distributionId
 * @param {string} [deps.name] label used in alert subjects
 */
const createBreaker = ({ getConfig, updateConfig, notify, distributionId, name = "endpoint" }) => {
  const setEnabled = async (enabled) => {
    const { ETag, DistributionConfig } = await getConfig(distributionId);
    if (DistributionConfig.Enabled === enabled) return false;
    DistributionConfig.Enabled = enabled;
    await updateConfig(distributionId, ETag, DistributionConfig);
    return true;
  };

  return async (event) => {
    // Re-enabling is deliberate: only a direct invoke with
    // {"action":"enable"} does it, never an alarm.
    const wantEnabled = event?.action === "enable";
    const trigger = describeTrigger(event);
    console.log(JSON.stringify({ msg: "breaker invoked", wantEnabled, trigger }));

    try {
      const changed = await setEnabled(wantEnabled);

      if (wantEnabled) {
        await notify(
          `[${name}] re-enabled`,
          changed
            ? `CloudFront distribution ${distributionId} re-enabled. ${name} is serving again.`
            : `CloudFront distribution ${distributionId} was already enabled. No change.`,
        );
        return { ok: true, enabled: true, changed };
      }

      await notify(
        changed ? `[${name}] BREAKER TRIPPED — disabled` : `[${name}] breaker re-fired`,
        changed
          ? `Cost circuit breaker tripped.\n\nCloudFront distribution ${distributionId} has been DISABLED; ` +
              `${name} is offline and accruing no further request charges.\n\nTrigger:\n${trigger}\n\n` +
              `Investigate the traffic source, then invoke this function with {"action":"enable"}.`
          : `Breaker fired but distribution ${distributionId} was already disabled.\n\nTrigger:\n${trigger}`,
      );
      return { ok: true, enabled: false, changed };
    } catch (err) {
      console.error("breaker failed", err);
      // The breaker failing is the one case a human must hear about at once.
      await notify(
        `[${name}] BREAKER FAILED — MANUAL ACTION REQUIRED`,
        `Could not disable distribution ${distributionId}.\n\nError: ${err?.name}: ${err?.message}\n\n` +
          `Trigger:\n${trigger}\n\nDisable it by hand now:\n` +
          `  aws cloudfront get-distribution-config --id ${distributionId}\n` +
          `  (set Enabled=false, then update-distribution --if-match <ETag>)`,
      );
      throw err;
    }
  };
};

const cf = new CloudFrontClient({});
const sns = new SNSClient({});

export const handler = createBreaker({
  distributionId: process.env.DISTRIBUTION_ID,
  name: process.env.NAME || "site",
  getConfig: (id) => cf.send(new GetDistributionConfigCommand({ Id: id })),
  updateConfig: (id, etag, config) =>
    cf.send(new UpdateDistributionCommand({ Id: id, IfMatch: etag, DistributionConfig: config })),
  notify: async (subject, message) => {
    try {
      await sns.send(new PublishCommand({ TopicArn: process.env.ALERT_TOPIC_ARN, Subject: subject.slice(0, 100), Message: message }));
    } catch (err) {
      console.error("failed to publish alert", err);
    }
  },
});
