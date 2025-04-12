import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import scheduleJob from "@salesforce/apex/DuplicateRecordScheduler.scheduleJob";

export default class ScheduleJobModal extends LightningElement {
  @api configId; // This should be the setting DeveloperName string

  jobName = "";
  scheduleType = "Daily";
  runHour = 2;
  isDryRun = false;

  get scheduleTypeOptions() {
    return [
      { label: "Daily", value: "Daily" },
      { label: "Weekly", value: "Weekly" },
      { label: "Custom (Cron)", value: "Custom" },
    ];
  }

  handleChange(event) {
    const { name, value, type, checked } = event.target;
    this[name] = type === "checkbox" ? checked : value;
  }

  async handleSubmit() {
    console.log(
      "handleSubmit called, jobName:",
      this.jobName,
      "configId:",
      this.configId,
    );

    // Validate each field individually to provide more specific error messages
    if (!this.jobName && !this.configId) {
      this.showToast(
        "Validation Error",
        "Job Name and Setting are required.",
        "error",
      );
      return;
    } else if (!this.jobName) {
      this.showToast("Validation Error", "Job Name is required.", "error");
      return;
    } else if (!this.configId) {
      this.showToast(
        "Validation Error",
        "No configuration selected. Please select a configuration and try again.",
        "error",
      );
      return;
    }

    try {
      const hour = parseInt(this.runHour, 10);

      // Validate hour
      if (isNaN(hour) || hour < 0 || hour > 23) {
        this.showToast(
          "Validation Error",
          "Run Hour must be a number between 0 and 23",
          "error",
        );
        return;
      }

      const cronExp = `0 0 ${hour} * * ?`; // CRON expression to run daily at the specified hour
      console.log("Generated cron expression:", cronExp);

      // Pass a single object containing all parameters to the Apex method
      const params = {
        jobName: this.jobName,
        cronExp: cronExp,
        settingDeveloperName: this.configId,
        isDryRun: this.isDryRun,
      };

      console.log("Calling scheduleJob with params:", params);

      await scheduleJob(params);

      console.log("Job scheduled successfully");
      this.showToast("Success", "Scheduled job created.", "success");
      this.dispatchEvent(new CustomEvent("jobscheduled"));
      this.close();
    } catch (error) {
      console.error("Error scheduling job:", error);
      let errorMessage = "An error occurred while scheduling the job";

      if (error.body?.message) {
        errorMessage = error.body.message;
      } else if (error.message) {
        errorMessage = error.message;
      }

      console.error("Error details:", errorMessage);
      this.showToast("Error", errorMessage, "error");
    }
  }

  close() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
