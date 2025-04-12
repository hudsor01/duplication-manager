({
  showToast: function (title, message, type) {
    var toastEvent = $A.get("e.force:showToast");
    toastEvent.setParams({
      title: title,
      message: message,
      type: type,
      mode: "dismissable",
    });
    toastEvent.fire();
  },

  loadSettings: function (component) {
    component.set("v.isLoading", true);

    var action = component.get("c.getActiveSettings");
    action.setCallback(this, function (response) {
      var state = response.getState();
      if (state === "SUCCESS") {
        component.set("v.settings", response.getReturnValue());
      } else {
        this.showToast(
          "Error",
          "Error loading settings: " + this.reduceError(response.getError()),
          "error",
        );
        console.error("Error loading settings", response.getError());
      }
      component.set("v.isLoading", false);
    });

    $A.enqueueAction(action);
  },

  loadScheduledJobs: function (component) {
    component.set("v.isLoading", true);

    var action = component.get("c.getScheduledJobs");
    action.setCallback(this, function (response) {
      var state = response.getState();
      if (state === "SUCCESS") {
        component.set("v.scheduledJobs", response.getReturnValue());
      } else {
        this.showToast(
          "Error",
          "Error loading scheduled jobs: " +
            this.reduceError(response.getError()),
          "error",
        );
        console.error("Error loading scheduled jobs", response.getError());
      }
      component.set("v.isLoading", false);
    });

    $A.enqueueAction(action);
  },

  reduceError: function (errors) {
    if (!Array.isArray(errors)) {
      return errors.message || JSON.stringify(errors);
    }

    return errors
      .filter(function (error) {
        return !!error;
      })
      .map(function (error) {
        if (typeof error === "string") return error;
        if (error.message) return error.message;
        if (error.body && error.body.message) return error.body.message;
        return JSON.stringify(error);
      })
      .join(", ");
  },
});
