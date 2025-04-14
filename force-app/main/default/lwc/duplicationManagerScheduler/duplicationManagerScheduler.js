import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import scheduleDuplicateFinderBatch from "@salesforce/apex/DuplicateRecordJobController.scheduleJob";

/**
 * Component for scheduling duplicate finder jobs
 * @component
 */
export default class DuplicationManagerScheduler extends LightningElement {
  @api setting;
  isLoading = false;

  // Schedule form data
  scheduleForm = {
    jobName: "",
    scheduleType: "daily",
    cronExpression: "0 0 8 * * ?", // Default: Daily at 8 AM
    hour: 8,
    dayOfWeek: "MON",
    isDryRun: true // Default: Dry run enabled
  };

  // Dropdown options
  scheduleTypeOptions = [
    { label: "Daily", value: "daily" },
    { label: "Weekly", value: "weekly" },
    { label: "Custom (Cron Expression)", value: "custom" }
  ];

  daysOfWeekOptions = [
    { label: "Sunday", value: "SUN" },
    { label: "Monday", value: "MON" },
    { label: "Tuesday", value: "TUE" },
    { label: "Wednesday", value: "WED" },
    { label: "Thursday", value: "THU" },
    { label: "Friday", value: "FRI" },
    { label: "Saturday", value: "SAT" }
  ];

  connectedCallback() {
    console.log("duplicateManagerScheduler component connected to DOM");
    if (this.setting) {
      this.scheduleForm.jobName = `${this.setting.ObjectApiName} Duplicate Finder`;
    }
  }

  renderedCallback() {
    const firstInput = this.template.querySelector("lightning-input");
    if (firstInput) {
      firstInput.focus();
    }
  }

  handleFormChange(event) {
    const field = event.target.dataset.field;
    if (field) {
      this.scheduleForm[field] = event.target.value;
    }
  }

  handleScheduleTypeChange(event) {
    this.scheduleForm.scheduleType = event.detail.value;
    if (this.scheduleForm.scheduleType === "daily") {
      this.scheduleForm.cronExpression = `0 0 ${this.scheduleForm.hour} * * ?`;
    } else if (this.scheduleForm.scheduleType === "weekly") {
      this.scheduleForm.cronExpression = `0 0 ${this.scheduleForm.hour} ? * ${this.scheduleForm.dayOfWeek}`;
    }
  }

  handleDryRunChange(event) {
    this.scheduleForm.isDryRun = event.target.checked;
  }

  handleSchedule() {
    console.log("handleSchedule called, setting:", this.setting);
    console.log("scheduleForm:", this.scheduleForm);

    // Validate required fields
    if (!this.scheduleForm.jobName) {
      this.showToast("Validation Error", "Job Name is required", "error");
      return;
    }

    if (!this.setting) {
      this.showToast(
        "Validation Error",
        "No configuration selected. Please select a configuration and try again.",
        "error"
      );
      return;
    }

    if (!this.setting.DeveloperName) {
      this.showToast(
        "Validation Error",
        "Selected configuration is missing required information (DeveloperName)",
        "error"
      );
      console.error("Setting is missing DeveloperName:", this.setting);
      return;
    }

    // Update cron expression based on schedule type
    if (this.scheduleForm.scheduleType === "daily") {
      this.scheduleForm.cronExpression = `0 0 ${this.scheduleForm.hour} * * ?`;
    } else if (this.scheduleForm.scheduleType === "weekly") {
      this.scheduleForm.cronExpression = `0 0 ${this.scheduleForm.hour} ? * ${this.scheduleForm.dayOfWeek}`;
    } else if (!this.scheduleForm.cronExpression) {
      this.showToast(
        "Validation Error",
        "Cron Expression is required for custom schedules",
        "error"
      );
      return;
    }

    // Scheduling job with cron expression

    this.isLoading = true;
    try {
      const params = {
        jobName: this.scheduleForm.jobName,
        cronExp: this.scheduleForm.cronExpression,
        settingDeveloperName: this.setting.DeveloperName,
        isDryRun: this.scheduleForm.isDryRun
      };

      // Schedule job with Apex

      scheduleDuplicateFinderBatch(params)
        .then((result) => {
          // Job scheduled successfully
          this.dispatchEvent(
            new CustomEvent("schedule", {
              detail: { jobId: result }
            })
          );
        })
        .catch((error) => {
          // Error occurred during scheduling
          this.handleError("Error scheduling job", error);
        })
        .finally(() => {
          this.isLoading = false;
        });
    } catch (error) {
      // Exception occurred during scheduling
      this.handleError("Error in schedule execution", error);
      this.isLoading = false;
    }
  }

  handleCancel() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: title,
        message: message,
        variant: variant
      })
    );
  }

  handleError(baseMessage, error) {
    let errorMessage = baseMessage;
    if (error) {
      if (error.body && error.body.message) {
        errorMessage += ": " + error.body.message;
      } else if (error.message) {
        errorMessage += ": " + error.message;
      } else {
        errorMessage += ": " + JSON.stringify(error);
      }
    }
    console.error(errorMessage);
    this.showToast("Error", errorMessage, "error");
  }

  get showCustomCron() {
    return this.scheduleForm.scheduleType === "custom";
  }

  get isDaily() {
    return this.scheduleForm.scheduleType === "daily";
  }

  get isWeekly() {
    return this.scheduleForm.scheduleType === "weekly";
  }
}
