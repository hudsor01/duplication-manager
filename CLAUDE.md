# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build/Test Commands

- `sf org list` - List available Salesforce orgs
- `sf project deploy start` - Deploy code to an org
- `sf apex test run -n ClassName` - Run a specific Apex test class
- `npm run test:unit` - Run LWC unit tests
- `npm run test:unit:watch` - Run LWC tests in watch mode
- `npm run lint` - Lint LWC code
- `npm run lint:fix` - Lint and auto-fix LWC code issues
- `npm run prettier` - Format all code with Prettier
- `git commit` - Will run pre-commit hooks to format and lint code

## Code Style Guidelines

- Use PascalCase for class names, camelCase for methods/variables
- Include class documentation with @author and @date annotations
- Add descriptive comments for complex logic
- Methods should follow single responsibility principle
- Include proper error handling with informative error messages
- Use consistent indentation (enforced by Prettier)
- Lightning Components follow "duplication[ComponentName]" naming pattern
- Validate inputs before use and handle edge cases
- When adding new components, follow existing patterns in the codebase
- For message passing between components, use Lightning Message Service
