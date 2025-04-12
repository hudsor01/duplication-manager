import { LightningElement, api } from "lwc";
import { formatNumber, formatPercentage } from "c/duplicationEnhancedUI";
import { loadScript } from "lightning/platformResourceLoader";
import chartjs from "@salesforce/resourceUrl/chartjs";

export default class DuplicationMetricsCard extends LightningElement {
  @api title = "Metric";
  @api value = 0;
  @api subtitle = "";
  @api footerText = "";
  @api iconName = "utility:chart";
  @api trend = 0;
  @api showTrend = false;
  @api showChart = false;
  @api chartData = [];
  @api format = "number"; // 'number', 'percentage', 'currency'
  @api decimals = 0;
  @api variant = "default"; // 'default', 'success', 'warning', 'danger'

  get formattedValue() {
    if (this.format === "percentage") {
      return formatPercentage(this.value, this.decimals);
    } else if (this.format === "currency") {
      return new Intl.NumberFormat("en-US", {
        style: "currency",
        currency: "USD",
        minimumFractionDigits: this.decimals,
        maximumFractionDigits: this.decimals,
      }).format(this.value);
    }
    return formatNumber(this.value, this.decimals);
  }

  get formattedTrend() {
    if (this.trend > 0) {
      return `+${formatPercentage(Math.abs(this.trend / 100), 1)}`;
    } else if (this.trend < 0) {
      return `-${formatPercentage(Math.abs(this.trend / 100), 1)}`;
    }
    return "0%";
  }

  get trendIcon() {
    return this.trend > 0
      ? "utility:arrowup"
      : this.trend < 0
        ? "utility:arrowdown"
        : "utility:dash";
  }

  get trendClass() {
    let baseClass = "trend-indicator slds-text-body_small ";

    if (this.trend > 0) {
      return baseClass + "slds-text-color_success";
    } else if (this.trend < 0) {
      return baseClass + "slds-text-color_error";
    }

    return baseClass + "slds-text-color_weak";
  }

  get iconVariant() {
    if (this.variant === "success") return "success";
    if (this.variant === "warning") return "warning";
    if (this.variant === "danger") return "error";
    return "default";
  }

  get chartColorClass() {
    let baseClass = "mini-chart ";

    if (this.variant === "success") return baseClass + "chart-success";
    if (this.variant === "warning") return baseClass + "chart-warning";
    if (this.variant === "danger") return baseClass + "chart-danger";
    return baseClass + "chart-default";
  }

  renderedCallback() {
    if (this.showChart && !this.chartInitialized) {
      this.initializeChart();
    }
  }

  chartInitialized = false;
  chart = null;

  initializeChart() {
    if (this.chartInitialized) return;

    loadScript(this, chartjs)
      .then(() => {
        // Get canvas element
        const canvas = this.template.querySelector("canvas.mini-chart");
        if (!canvas) return;

        // Get chart context
        const ctx = canvas.getContext("2d");

        // Default data if none provided
        const chartValues =
          this.chartData.length > 0
            ? this.chartData
            : [5, 10, 15, 20, 25, 30, 25, 20, 15];

        // Get chart color based on variant
        let chartColor;
        switch (this.variant) {
          case "success":
            chartColor = "rgba(75, 202, 129, 1)";
            break;
          case "warning":
            chartColor = "rgba(255, 183, 93, 1)";
            break;
          case "danger":
            chartColor = "rgba(230, 74, 74, 1)";
            break;
          default:
            chartColor = "rgba(21, 137, 238, 1)";
        }

        // Create chart configuration
        const config = {
          type: "line",
          data: {
            labels: Array(chartValues.length).fill(""),
            datasets: [
              {
                data: chartValues,
                borderColor: chartColor,
                backgroundColor: chartColor.replace("1)", "0.1)"),
                fill: true,
                tension: 0.4,
                pointRadius: 0,
                borderWidth: 2,
              },
            ],
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
              legend: { display: false },
              tooltip: { enabled: false },
            },
            scales: {
              x: { display: false },
              y: { display: false },
            },
            animation: false,
          },
        };

        // Initialize the chart
        this.chart = new window.Chart(ctx, config);
        this.chartInitialized = true;
      })
      .catch((error) => {
        console.error("Error loading Chart.js", error);
      });
  }

  @api
  updateChartData(newData) {
    if (!this.chart || !newData) return;

    this.chart.data.datasets[0].data = newData;
    this.chart.update();
  }
}
