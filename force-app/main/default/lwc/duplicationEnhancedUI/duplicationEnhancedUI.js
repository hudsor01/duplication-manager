/**
 * Enhanced UI components and utilities for duplicate Manager
 */
import { LightningElement, api } from "lwc";

/**
 * Generate status badge CSS class based on status
 * @param {string} status - Status value
 * @returns {string} CSS class for badge
 */
export function getStatusBadgeClass(status) {
  if (!status) return "slds-badge";

  const statusLower = status.toLowerCase();
  let badgeClass = "slds-badge ";

  if (statusLower.includes("success") || statusLower.includes("completed")) {
    badgeClass += "slds-badge_success";
  } else if (statusLower.includes("warning")) {
    badgeClass += "slds-theme_warning";
  } else if (statusLower.includes("error") || statusLower.includes("failed")) {
    badgeClass += "slds-badge_error";
  } else if (
    statusLower.includes("processing") ||
    statusLower.includes("running")
  ) {
    badgeClass += "slds-badge_inverse";
  } else {
    badgeClass += "slds-badge_lightest";
  }

  return badgeClass;
}

/**
 * Format a date for display
 * @param {string|Date} dateValue - Date to format
 * @param {string} format - Format type ('short', 'medium', 'long')
 * @returns {string} Formatted date
 */
export function formatDate(dateValue, format = "medium") {
  if (!dateValue) return "";

  const date = typeof dateValue === "string" ? new Date(dateValue) : dateValue;

  if (!(date instanceof Date) || isNaN(date)) {
    return "";
  }

  let options = {};

  switch (format) {
    case "short":
      options = { month: "numeric", day: "numeric", year: "2-digit" };
      break;
    case "long":
      options = {
        weekday: "long",
        year: "numeric",
        month: "long",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit"
      };
      break;
    case "time":
      options = { hour: "2-digit", minute: "2-digit" };
      break;
    case "medium":
    default:
      options = {
        year: "numeric",
        month: "short",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit"
      };
  }

  return new Intl.DateTimeFormat("en-US", options).format(date);
}

/**
 * Format a number with commas and decimal places
 * @param {number} value - Number to format
 * @param {number} decimals - Number of decimal places
 * @returns {string} Formatted number
 */
export function formatNumber(value, decimals = 0) {
  if (value === undefined || value === null) return "";

  return Number(value).toLocaleString("en-US", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals
  });
}

/**
 * Format percentage values
 * @param {number} value - Value to format as percentage
 * @param {number} decimals - Number of decimal places
 * @returns {string} Formatted percentage
 */
export function formatPercentage(value, decimals = 1) {
  if (value === undefined || value === null) return "";

  return Number(value).toLocaleString("en-US", {
    style: "percent",
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals
  });
}

/**
 * Truncate text with ellipsis
 * @param {string} text - Text to truncate
 * @param {number} length - Maximum length before truncation
 * @returns {string} Truncated text
 */
export function truncateText(text, length = 50) {
  if (!text || text.length <= length) return text || "";

  return text.substring(0, length) + "...";
}

/**
 * Format field name for display
 * @param {string} fieldName - API field name
 * @returns {string} Formatted field name
 */
export function formatFieldName(fieldName) {
  if (!fieldName) return "";

  // Remove namespace prefix if present
  let name = fieldName.includes("__") ? fieldName.split("__").pop() : fieldName;

  // Remove __c suffix
  name = name.replace(/__c$/i, "");

  // Split by capital letters and underscores
  name = name
    .replace(/_/g, " ")
    .replace(/([A-Z])/g, " $1")
    .trim();

  // Capitalize first letter
  return name.charAt(0).toUpperCase() + name.slice(1);
}

/**
 * Progress ring component
 */
export default class DuplicationProgressRing extends LightningElement {
  @api percentage = 0;
  @api size = "medium";
  @api variant = "default";

  get computedStyle() {
    const normalizedPercentage = Math.min(100, Math.max(0, this.percentage));
    const degrees = 360 * (normalizedPercentage / 100);
    return `--progress-angle: ${degrees}deg;`;
  }

  get ringClass() {
    let classes = "progress-ring";

    if (this.size) {
      classes += ` progress-ring_${this.size}`;
    }

    if (this.variant) {
      classes += ` progress-ring_${this.variant}`;
    }

    return classes;
  }

  get formattedPercentage() {
    return `${Math.round(this.percentage)}%`;
  }
}
