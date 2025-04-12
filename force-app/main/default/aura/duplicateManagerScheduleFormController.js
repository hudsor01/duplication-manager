({
  handleScheduleTypeChange: function (component, event, helper) {
    var scheduleType = event.getParam("value");
    component.set("v.scheduleType", scheduleType);

    // Update cron expression based on type
    if (scheduleType === "daily") {
      var hour = component.get("v.hour");
      component.set("v.cronExpression", "0 0 " + hour + " * * ?");
    } else if (scheduleType === "weekly") {
      var hour = component.get("v.hour");
      var dayOfWeek = component.get("v.dayOfWeek");
      component.set("v.cronExpression", "0 0 " + hour + " ? * " + dayOfWeek);
    }
  },

  getFormData: function (component, event, helper) {
    var jobName = component.find("jobName").get("v.value");
    var scheduleType = component.get("v.scheduleType");
    var cronExpression = component.get("v.cronExpression");
    var isDryRun = component.find("isDryRun").get("v.value");

    // Validate form
    var isValid = true;

    if (!jobName || jobName.trim() === "") {
      isValid = false;
    }

    if (scheduleType === "daily" || scheduleType === "weekly") {
      var hour = component.get("v.hour");

      // Update cron expression based on selected values
      if (scheduleType === "daily") {
        cronExpression = "0 0 " + hour + " * * ?";
      } else {
        var dayOfWeek = component.get("v.dayOfWeek");
        cronExpression = "0 0 " + hour + " ? * " + dayOfWeek;
      }
    }

    return {
      jobName: jobName,
      scheduleType: scheduleType,
      cronExpression: cronExpression,
      isDryRun: isDryRun,
      isValid: isValid,
    };
  },
});
