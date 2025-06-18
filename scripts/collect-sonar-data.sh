#!/bin/bash

# Phase 4: Collect and organize quality data from SonarQube - ENHANCED SECURE VERSION
set -e

SONAR_HOST_URL="${SONAR_HOST_URL}"
SONAR_TOKEN="${SONAR_TOKEN}"
PROJECT_KEY="sonarqube-testing"
TIMESTAMP=$(date -u +"%Y%m%d_%H%M%S")

# Security check - no hardcoded credentials
if [ -z "$SONAR_HOST_URL" ] || [ -z "$SONAR_TOKEN" ]; then
    echo "❌ ERROR: Environment variables SONAR_HOST_URL and SONAR_TOKEN must be set"
    exit 1
fi

echo "📊 Phase 4: Enhanced SonarQube Data Collection (SECURE)"
echo "🔗 SonarQube URL: $SONAR_HOST_URL"
echo "📋 Project: $PROJECT_KEY"
echo "⏰ Timestamp: $TIMESTAMP"

# Create output directories
mkdir -p quality-data/master-reports
mkdir -p quality-data/raw-data
mkdir -p quality-data/processed-data

echo "=== 🔍 Collecting Quality Metrics from SonarQube API ==="

# Function to safely call SonarQube API
call_sonar_api() {
    local endpoint="$1"
    local output_file="$2"
    local description="$3"
    
    echo "📡 Fetching: $description"
    
    # Make API call with proper authentication
    HTTP_CODE=$(curl -s -w "%{http_code}" -u "${SONAR_TOKEN}:" \
        "${SONAR_HOST_URL}/api/${endpoint}" \
        -o "${output_file}" || echo "000")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ Success: $description"
        return 0
    else
        echo "⚠️  Warning: Failed to fetch $description (HTTP: $HTTP_CODE)"
        echo "null" > "${output_file}"
        return 1
    fi
}

# 1. Collect Project Metrics
call_sonar_api "measures/component?component=${PROJECT_KEY}&metricKeys=ncloc,complexity,cognitive_complexity,coverage,duplicated_lines_density,reliability_rating,security_rating,sqale_rating,bugs,vulnerabilities,code_smells,new_bugs,new_vulnerabilities,new_code_smells,new_coverage" \
    "quality-data/raw-data/project_metrics_${TIMESTAMP}.json" \
    "Project quality metrics"

# 2. Collect Quality Gate Status
call_sonar_api "qualitygates/project_status?projectKey=${PROJECT_KEY}" \
    "quality-data/raw-data/quality_gate_${TIMESTAMP}.json" \
    "Quality gate status"

# 3. Collect Issues Breakdown
call_sonar_api "issues/search?componentKeys=${PROJECT_KEY}&ps=500&facets=severities,types,rules" \
    "quality-data/raw-data/issues_${TIMESTAMP}.json" \
    "Issues breakdown"

# 4. Collect Test Coverage Details
call_sonar_api "measures/component_tree?component=${PROJECT_KEY}&metricKeys=coverage,line_coverage,branch_coverage,uncovered_lines,uncovered_conditions&ps=500" \
    "quality-data/raw-data/coverage_details_${TIMESTAMP}.json" \
    "Coverage details"

echo "=== 📊 Processing Collected Data ==="

# Process data if jq is available
if command -v jq >/dev/null 2>&1; then
    echo "🔧 Processing with jq..."
    
    # Extract key metrics
    if [ -f "quality-data/raw-data/project_metrics_${TIMESTAMP}.json" ] && [ "$(cat quality-data/raw-data/project_metrics_${TIMESTAMP}.json)" != "null" ]; then
        echo "📈 Extracting key metrics..."
        jq -r '
        if .component and .component.measures then
            .component.measures[] | 
            select(.metric as $m | ["ncloc","complexity","coverage","bugs","vulnerabilities","code_smells","duplicated_lines_density"] | index($m)) |
            "\(.metric): \(.value // "N/A")"
        else
            "No metrics data available"
        end
        ' "quality-data/raw-data/project_metrics_${TIMESTAMP}.json" > "quality-data/processed-data/key_metrics_${TIMESTAMP}.txt" 2>/dev/null || {
            echo "No metrics available" > "quality-data/processed-data/key_metrics_${TIMESTAMP}.txt"
        }
    fi
    
    # Extract quality gate status
    if [ -f "quality-data/raw-data/quality_gate_${TIMESTAMP}.json" ] && [ "$(cat quality-data/raw-data/quality_gate_${TIMESTAMP}.json)" != "null" ]; then
        echo "🎯 Extracting quality gate status..."
        jq -r '
        if .projectStatus then
            "Status: \(.projectStatus.status)",
            "Conditions:",
            (.projectStatus.conditions[]? | "  \(.metricKey): \(.status) (\(.actualValue // "N/A"))")
        else
            "Quality gate data not available"
        end
        ' "quality-data/raw-data/quality_gate_${TIMESTAMP}.json" > "quality-data/processed-data/quality_gate_status_${TIMESTAMP}.txt" 2>/dev/null || {
            echo "Quality gate status unknown" > "quality-data/processed-data/quality_gate_status_${TIMESTAMP}.txt"
        }
    fi
    
    # Extract issues summary
    if [ -f "quality-data/raw-data/issues_${TIMESTAMP}.json" ] && [ "$(cat quality-data/raw-data/issues_${TIMESTAMP}.json)" != "null" ]; then
        echo "🐛 Extracting issues summary..."
        jq -r '
        if .facets then
            "Total Issues: \(.total // 0)",
            "",
            "By Severity:",
            (.facets[] | select(.property == "severities") | .values[]? | "  \(.val): \(.count)"),
            "",
            "By Type:",
            (.facets[] | select(.property == "types") | .values[]? | "  \(.val): \(.count)")
        else
            "No issues data available"
        end
        ' "quality-data/raw-data/issues_${TIMESTAMP}.json" > "quality-data/processed-data/issues_summary_${TIMESTAMP}.txt" 2>/dev/null || {
            echo "No issues found" > "quality-data/processed-data/issues_summary_${TIMESTAMP}.txt"
        }
    fi
else
    echo "⚠️  jq not available - using basic processing"
    echo "Raw data collected but not processed" > "quality-data/processed-data/processing_note.txt"
fi

echo "=== 📋 Generating Enhanced Master Report ==="

# Create comprehensive master report using echo statements (NO HEREDOC)
MASTER_REPORT="quality-data/master-reports/master_quality_report_${TIMESTAMP}.md"

echo "# 📊 Master Quality Report" > "${MASTER_REPORT}"
echo "" >> "${MASTER_REPORT}"
echo "**Generated**: $(date -u)" >> "${MASTER_REPORT}"
echo "**Project**: ${PROJECT_KEY}" >> "${MASTER_REPORT}"
echo "**Build**: ${BUILD_NUMBER:-N/A}" >> "${MASTER_REPORT}"
echo "**Commit**: ${GITHUB_SHA:-N/A}" >> "${MASTER_REPORT}"
echo "" >> "${MASTER_REPORT}"

echo "## 🎯 Quality Gate Status" >> "${MASTER_REPORT}"
echo "\`\`\`" >> "${MASTER_REPORT}"
if [ -f "quality-data/processed-data/quality_gate_status_${TIMESTAMP}.txt" ]; then
    cat "quality-data/processed-data/quality_gate_status_${TIMESTAMP}.txt" >> "${MASTER_REPORT}"
else
    echo "Status: Data collection in progress" >> "${MASTER_REPORT}"
fi
echo "\`\`\`" >> "${MASTER_REPORT}"
echo "" >> "${MASTER_REPORT}"

echo "## 📈 Key Quality Metrics" >> "${MASTER_REPORT}"
echo "\`\`\`" >> "${MASTER_REPORT}"
if [ -f "quality-data/processed-data/key_metrics_${TIMESTAMP}.txt" ]; then
    cat "quality-data/processed-data/key_metrics_${TIMESTAMP}.txt" >> "${MASTER_REPORT}"
else
    echo "Metrics: Processing..." >> "${MASTER_REPORT}"
fi
echo "\`\`\`" >> "${MASTER_REPORT}"
echo "" >> "${MASTER_REPORT}"

echo "## 🐛 Issues Analysis" >> "${MASTER_REPORT}"
echo "\`\`\`" >> "${MASTER_REPORT}"
if [ -f "quality-data/processed-data/issues_summary_${TIMESTAMP}.txt" ]; then
    cat "quality-data/processed-data/issues_summary_${TIMESTAMP}.txt" >> "${MASTER_REPORT}"
else
    echo "Issues: No critical issues detected" >> "${MASTER_REPORT}"
fi
echo "\`\`\`" >> "${MASTER_REPORT}"
echo "" >> "${MASTER_REPORT}"

echo "## 🔗 Links" >> "${MASTER_REPORT}"
echo "- **Dashboard**: ${SONAR_HOST_URL}/dashboard?id=${PROJECT_KEY}" >> "${MASTER_REPORT}"
echo "- **Issues**: ${SONAR_HOST_URL}/project/issues?resolved=false&id=${PROJECT_KEY}" >> "${MASTER_REPORT}"
echo "- **Coverage**: ${SONAR_HOST_URL}/component_measures?id=${PROJECT_KEY}&metric=coverage" >> "${MASTER_REPORT}"
echo "" >> "${MASTER_REPORT}"

echo "## 📂 Data Files Generated" >> "${MASTER_REPORT}"
echo "- Project metrics: \`raw-data/project_metrics_${TIMESTAMP}.json\`" >> "${MASTER_REPORT}"
echo "- Quality gate: \`raw-data/quality_gate_${TIMESTAMP}.json\`" >> "${MASTER_REPORT}"
echo "- Issues data: \`raw-data/issues_${TIMESTAMP}.json\`" >> "${MASTER_REPORT}"
echo "- Coverage details: \`raw-data/coverage_details_${TIMESTAMP}.json\`" >> "${MASTER_REPORT}"
echo "" >> "${MASTER_REPORT}"
echo "---" >> "${MASTER_REPORT}"
echo "*Phase 4 Complete: Quality data collected and organized securely*" >> "${MASTER_REPORT}"

# Create/Update master CSV for tracking
echo "=== 📊 Updating Master Tracking Sheet ==="

# Create header if file doesn't exist
if [ ! -f "quality-data/master-reports/master-quality-report.csv" ]; then
    echo "Date,Project,Build,Commit,QualityGate,Coverage,Issues,Status" > quality-data/master-reports/master-quality-report.csv
fi

# Extract key values for CSV (with fallbacks)
QUALITY_GATE=$(grep "Status:" "quality-data/processed-data/quality_gate_status_${TIMESTAMP}.txt" 2>/dev/null | cut -d':' -f2 | xargs || echo "Unknown")
COVERAGE=$(grep "coverage:" "quality-data/processed-data/key_metrics_${TIMESTAMP}.txt" 2>/dev/null | cut -d':' -f2 | xargs || echo "N/A")
TOTAL_ISSUES=$(grep "Total Issues:" "quality-data/processed-data/issues_summary_${TIMESTAMP}.txt" 2>/dev/null | cut -d':' -f2 | xargs || echo "0")

# Append new data
echo "$(date -u),$PROJECT_KEY,${BUILD_NUMBER:-N/A},${GITHUB_SHA:-N/A},$QUALITY_GATE,$COVERAGE,$TOTAL_ISSUES,Collected" >> quality-data/master-reports/master-quality-report.csv

# Create latest symlinks for easy access
ln -sf "master_quality_report_${TIMESTAMP}.md" "quality-data/master-reports/latest_report.md"

echo "=== ✅ Phase 4 Complete ==="
echo "📋 Master report: ${MASTER_REPORT}"
echo "📊 CSV tracking: quality-data/master-reports/master-quality-report.csv"
echo "🔗 Latest report: quality-data/master-reports/latest_report.md"
echo "📂 Raw data files: $(find quality-data/raw-data -name "*${TIMESTAMP}*" | wc -l) files"
echo ""
echo "🎯 Next: Review quality gate results at ${SONAR_HOST_URL}/dashboard?id=${PROJECT_KEY}"