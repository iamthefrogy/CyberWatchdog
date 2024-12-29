#!/bin/bash

# Set up color variables
YELLOW='\033[1;93m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Fetch GitHub Token from environment variable
if [[ -z "$PAT_TOKEN" ]]; then
    echo -e "${RED}Error: PAT_TOKEN environment variable is not set. Exiting.${NC}"
    exit 1
fi

GITHUB_TOKEN="$PAT_TOKEN"

# Check rate limit
rate_limit_response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/rate_limit")
remaining=$(echo "$rate_limit_response" | jq -r '.rate.remaining // 0')
reset_time=$(echo "$rate_limit_response" | jq -r '.rate.reset // 0')

if [[ "$remaining" -eq 0 ]]; then
    reset_time_human=$(date -d "@$reset_time" "+%Y-%m-%d %H:%M:%S")
    echo -e "${RED}Rate limit exceeded. Try again after: $reset_time_human${NC}"
    exit 1
fi

# Hardcoded topic
input="cyber"
topic=$(echo "$input" | tr '[:upper:]' '[:lower:]' | tr " " "+")

# Fetch the total count of repositories
echo -e "${YELLOW}Fetching repository information for topic: ${GREEN}${input}${NC}"
response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/search/repositories?q=stars%3A%3E50+$topic+sort:stars&per_page=5")

# Validate the API response
if ! echo "$response" | jq -e . > /dev/null 2>&1; then
    echo -e "${RED}Error: Failed to fetch data from GitHub API. Please check your internet connection or GitHub token.${NC}"
    exit 1
fi

# Extract total count and validate
tpc=$(echo "$response" | jq -r '.total_count // 0')
if [[ "$tpc" -eq 0 ]]; then
    echo -e "${RED}No repositories found for the topic '${input}'.${NC}"
    exit 1
fi

# Calculate pages needed
pg=$(( (tpc + 99) / 100 ))

# Initialize README.md
rm -f README.md  # Remove any existing file
echo "# **CyberWatchdog** 🐾🔍" > README.md
echo "" >> README.md
echo "**CyberWatchdog** is your daily tracker for the top GitHub repositories related to **cybersecurity**. By monitoring and curating trending repositories, CyberWatchdog ensures you stay up-to-date with the latest tools, frameworks, and research in the cybersecurity domain." >> README.md
echo "" >> README.md
echo "---" >> README.md
echo "" >> README.md
echo "## **Top Cybersecurity Repositories (Updated: $(date '+%Y-%m-%d'))**" >> README.md
echo "" >> README.md
echo "| Repository (Link)                        | Stars   | Forks   | Description                     | Last Updated |" >> README.md
echo "|------------------------------------------|---------|---------|---------------------------------|--------------|" >> README.md

# Fetch repositories and format output
empty_pages=0  # Counter for consecutive empty pages

for i in $(seq 1 $pg); do
    page_response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/search/repositories?q=stars%3A%3E50+$topic+sort:stars&per_page=100&page=$i")
    echo "$page_response" > debug_page_response.json  # Debugging: Save raw response

    # Validate the response
    if ! echo "$page_response" | jq -e '.items | length > 0' > /dev/null 2>&1; then
        echo -e "${RED}No repositories found or invalid response on page $i.${NC}"
        empty_pages=$((empty_pages + 1))

        # Exit early if multiple consecutive empty pages
        if [[ $empty_pages -ge 3 ]]; then
            echo -e "${YELLOW}Exiting early: Detected 3 consecutive empty pages.${NC}"
            break
        fi
        continue
    fi

    empty_pages=0  # Reset counter if valid repositories are found

    # Process repository information
    echo "$page_response" | jq -c '.items[]' | while read -r line; do
        name=$(echo "$line" | jq -r '.name // "Unknown"')
        owner=$(echo "$line" | jq -r '.owner.login // "Unknown"')
        stars=$(echo "$line" | jq -r '.stargazers_count // 0')
        forks=$(echo "$line" | jq -r '.forks_count // 0')
        desc=$(echo "$line" | jq -r '.description // "No description"')
        updated=$(echo "$line" | jq -r '.updated_at // "1970-01-01T00:00:00Z"')
        url=$(echo "$line" | jq -r '.html_url // "#"')

        # Truncate long descriptions
        short_desc=$(echo "$desc" | cut -c 1-50)
        [ ${#desc} -gt 50 ] && short_desc="$short_desc..."

        # Cross-platform date formatting
        if [[ "$OSTYPE" == "darwin"* ]]; then
            updated_date=$(echo "$updated" | awk '{print $1}' | xargs -I {} date -u -jf "%Y-%m-%dT%H:%M:%SZ" {} "+%Y-%m-%d")
        else
            updated_date=$(date -d "$updated" "+%Y-%m-%d")
        fi

        # Format the table row
        printf "| [%s](%s) | %-7s | %-7s | %-31s | %-12s |\n" "$name" "$url" "$stars" "$forks" "$short_desc" "$updated_date" >> README.md
    done
done

# Display summary and push updates
if [ -s README.md ]; then
    echo -e "${GREEN}Successfully updated README.md with top repositories for '$input'.${NC}"

    # Set user details for commit
    git config --global user.email "github-actions@github.com"
    git config --global user.name "GitHub Actions Bot"

    # Commit and push changes to GitHub
    git add README.md
    git commit -m "Update README with top repositories for '$input'"
    git push origin main
else
    echo -e "${RED}Error: No repositories were written to README.md.${NC}"
    exit 1
fi
