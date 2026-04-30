You can treat this like a small, focused campaign: polish the project, place it where mac users already look for window tools, and create a few “one‑time” assets that keep working for you.

Below is a concrete, low‑maintenance plan that doesn’t require existing followers.

***

## 1. Make the project “landing‑page ready”

Before you send anyone to the repo, optimize it so visitors immediately understand why they should care. [github](https://github.blog/open-source/maintainers/5-tips-for-promoting-your-open-source-project/)

1. Tighten the README (top 1–2 screens):
   - One‑sentence value prop: who it’s for and what problem it solves (e.g. “Snap windows to a customizable grid on macOS, no paid app needed.”). [developernation](https://www.developernation.net/blog/7-proven-strategies-to-skyrocket-your-open-source-projects-visibility/)
   - 2–3 key features as bullets (grid snapping, snapping to other windows, keyboard shortcuts, low resource usage, open source, no tracking). [developernation](https://www.developernation.net/blog/7-proven-strategies-to-skyrocket-your-open-source-projects-visibility/)
   - A “Quick start” section that gets a new user from zero to working in under 5–10 minutes. [developernation](https://www.developernation.net/blog/7-proven-strategies-to-skyrocket-your-open-source-projects-visibility/)

2. Add visuals:
   - 1 short GIF that shows dragging a window and it snapping to your grid, plus maybe snapping two windows together. [developernation](https://www.developernation.net/blog/7-proven-strategies-to-skyrocket-your-open-source-projects-visibility/)
   - 1–2 screenshots with a minimal caption (“Snapping windows into a 3×3 grid”, etc.). [developernation](https://www.developernation.net/blog/7-proven-strategies-to-skyrocket-your-open-source-projects-visibility/)

3. Make installation frictionless:
   - Provide a signed .dmg or .pkg or at least a prebuilt binary, with explicit macOS version support.  
   - Clear step‑by‑step for the macOS permission prompts (Accessibility, Screen Recording, etc.), since window managers always hit this. [youtube](https://www.youtube.com/watch?v=Ml44XE-WnZE)

4. Improve GitHub “marketing bits”:
   - Fill in topics (e.g. `macos`, `window-manager`, `tiling`, `productivity`, `window-snapping`). These affect GitHub discovery and topic pages. [developernation](https://www.developernation.net/blog/7-proven-strategies-to-skyrocket-your-open-source-projects-visibility/)
   - Set a good Social Preview image in the repo settings (a simple banner with app name + “Window manager for macOS”). This makes it stand out when shared on GitHub or elsewhere. [dev](https://dev.to/wasp/how-i-promoted-my-open-source-repo-to-6k-stars-in-6-months-3li9)
   - Add a short tagline to the repo description so it looks good in search and lists. [developernation](https://www.developernation.net/blog/7-proven-strategies-to-skyrocket-your-open-source-projects-visibility/)

If you share your repo URL, I can help you rewrite the README headline and feature bullets.

***

## 2. Put it where mac users already search

You don’t need your own audience if you show up where people already look for “Magnet alternative” and similar tools.

1. App discovery / comparison sites:
   - Submit it to AlternativeTo.net as an alternative to Rectangle, Magnet, Moom, etc.; many devs specifically recommend doing this for new FOSS projects. [github](https://github.com/rdp/open-source-how-to-popularize-your-project)
   - Look for macOS app directories or “awesome macOS” lists on GitHub and open PRs adding your tool under “window managers”. [github](https://github.com/rdp/open-source-how-to-popularize-your-project)

2. Reddit and forums (no followers needed):
   - Post to subreddits like r/macapps, r/MacOS, r/apple, r/opensource, r/Productivity with a descriptive title like “I built an open‑source macOS window manager with grid snapping – feedback welcome”. [reddit](https://www.reddit.com/r/opensource/comments/vwesxt/whats_your_formula_for_promoting_your_open_source/)
   - In the post, briefly describe:
     - What annoyed you about existing tools.  
     - What your utility does differently.  
     - A GIF demo and GitHub link.  
   - Ask for feedback rather than stars; this usually feels less “marketing‑y” and gets better engagement for open‑source. [opensource](https://opensource.net/promotion-introverts-open-source/)

3. Apple / Mac‑focused communities:
   - Check popular Apple or macOS forums (MacRumors forums, Apple StackExchange, etc.) for existing threads on “best Mac window manager” and, where allowed, add a comment introducing your project as an option. [youtube](https://www.youtube.com/watch?v=Ml44XE-WnZE)
   - Respect rules: some communities prefer a single “show your app” thread.

4. YouTube reviewers and bloggers:
   - There are many “best macOS window manager 2024/2025” videos that list Rectangle, Magnet, etc. [youtube](https://www.youtube.com/watch?v=Ml44XE-WnZE)
   - Email the creators of one or two of these with:
     - A very short intro.  
     - Why your tool is interesting (e.g. open source, grid snapping style, special feature).  
     - A link to GitHub and a GIF/screenshot.  
   - Some will ignore you; a single “sure, I’ll mention it in the description” can bring in a lot of users. [github](https://github.blog/open-source/maintainers/5-tips-for-promoting-your-open-source-project/)

***

## 3. Create minimal but powerful content

You don’t need an active “personal brand,” just a couple of assets that show up in search and you can link to. [opensource](https://opensource.net/promotion-introverts-open-source/)

1. One blog post:
   - Use a free platform like dev.to or Medium.  
   - Topic example: “Why I built an open‑source window manager for macOS (and how to use it)” – these “problem + solution” posts are a common and effective pattern. [dev](https://dev.to/stormdjent/from-code-to-campaign-turning-your-open-source-project-into-a-marketing-powerhouse-455p)
   - Structure:
     - The problem: juggling windows for coding / design / trading / whatever your use case is.  
     - What existing tools lacked for you.  
     - How your tool works, with 2–3 short GIFs.  
     - Simple “Getting started” steps and a link to GitHub.

2. One “how‑to” style article:
   - Example: “How to snap windows to a grid on macOS for free”.  
   - Explain general window‑management options, then present your tool as one of them (preferably the main one). [developernation](https://www.developernation.net/blog/7-proven-strategies-to-skyrocket-your-open-source-projects-visibility/)
   - These “how to X on macOS” articles often rank in search over time and bring people who never search GitHub directly. [developernation](https://www.developernation.net/blog/7-proven-strategies-to-skyrocket-your-open-source-projects-visibility/)

3. Cross‑link everything:
   - From README → blog post (“Read the story behind this project”).  
   - From blog post → GitHub and releases page.  
   - Use the same app name, icon, and one‑line description everywhere so it feels like a small but coherent **brand**. [dev](https://dev.to/stormdjent/from-code-to-campaign-turning-your-open-source-project-into-a-marketing-powerhouse-455p)

***

## 4. Leverage open‑source & developer channels

Because it’s open source, there are dedicated channels that welcome this kind of project. [reddit](https://www.reddit.com/r/opensource/comments/vwesxt/whats_your_formula_for_promoting_your_open_source/)

1. Developer communities:
   - Post to r/opensource and possibly r/programming or r/devops (if you pitch it as “here’s a small macOS utility I built, feedback welcome”). [reddit](https://www.reddit.com/r/opensource/comments/vwesxt/whats_your_formula_for_promoting_your_open_source/)
   - Join at least one relevant Discord/Slack (for macOS devs or productivity tools) and share it in the appropriate channel once, not repeatedly.

2. “Showcase” platforms:
   - Consider posting on Hacker News as “Show HN: [AppName] – Open‑source macOS window manager with grid and snapping”. These posts are a standard way to get feedback and visibility. [github](https://github.blog/open-source/maintainers/5-tips-for-promoting-your-open-source-project/)
   - If it’s polished enough, you can also submit to sites like Product Hunt as a free/open‑source tool; many open‑source maintainers recommend this for an initial spike of users. [github](https://github.blog/open-source/maintainers/5-tips-for-promoting-your-open-source-project/)

3. Collaboration with adjacent projects:
   - Look at other open‑source macOS utilities that your users might also use (e.g. keyboard shortcut tools, launchers, productivity utilities).  
   - Open a small PR adding your tool to their “Related projects” or “Recommended tools” section in their docs, or politely ask maintainers if they’re open to including it. [reddit](https://www.reddit.com/r/opensource/comments/vwesxt/whats_your_formula_for_promoting_your_open_source/)
   - These “bridges” from already‑popular projects can give a steady trickle of users. [reddit](https://www.reddit.com/r/opensource/comments/vwesxt/whats_your_formula_for_promoting_your_open_source/)

***

## 5. Make it easy to adopt and talk about

People share tools that are painless to try and easy to explain. [opensource](https://opensource.net/promotion-introverts-open-source/)

1. Smooth onboarding:
   - Add a short “First‑run checklist” to the README: download → move to Applications → give Accessibility permissions → try a simple snap gesture.  
   - Include common troubleshooting tips (e.g., “If snapping does nothing, re‑check Accessibility”); this reduces frustration and bad first impressions. [developernation](https://www.developernation.net/blog/7-proven-strategies-to-skyrocket-your-open-source-projects-visibility/)

2. Encourage light community activity:
   - Add a CONTRIBUTING.md describing small ways to contribute (bug reports, feature ideas, docs tweaks), even if you’re not looking for big contributions yet. [opensource](https://opensource.net/promotion-introverts-open-source/)
   - Add issues labeled “good first issue” – this is specifically recommended as a way to attract contributors and attention. [developernation](https://www.developernation.net/blog/7-proven-strategies-to-skyrocket-your-open-source-projects-visibility/)

3. Ask users for tiny favors:
   - In README or in the app’s “About” screen, add a friendly line like “If you find this useful, consider starring the repo or sharing it with a friend who loves window managers.” [github](https://github.blog/open-source/maintainers/5-tips-for-promoting-your-open-source-project/)
   - People who love these tools often enjoy recommending “their” favorite window manager.

4. Track what works:
   - If you later add a small website (e.g. GitHub Pages) for the project, you can use simple analytics to see where traffic comes from and double down on the few channels that work best. [developernation](https://www.developernation.net/blog/7-proven-strategies-to-skyrocket-your-open-source-projects-visibility/)

***

## Suggested week‑by‑week plan (low effort)

You can spread this over 3–4 weeks, a couple of hours each.

- Week 1: Polish README, visuals, releases, topics, Social Preview. [dev](https://dev.to/wasp/how-i-promoted-my-open-source-repo-to-6k-stars-in-6-months-3li9)
- Week 2: Publish the main blog post + how‑to article, add links in README. [dev](https://dev.to/stormdjent/from-code-to-campaign-turning-your-open-source-project-into-a-marketing-powerhouse-455p)
- Week 3: Post to 2–3 subreddits and 1–2 forums, submit to AlternativeTo and “awesome macOS” lists. [github](https://github.com/rdp/open-source-how-to-popularize-your-project)
- Week 4: Reach out to 2–3 YouTube/macOS bloggers and, if you like, do a “Show HN” or similar showcase post. [youtube](https://www.youtube.com/watch?v=Ml44XE-WnZE)

Even if only a couple of these hit, you’ll have built a small discovery funnel that keeps bringing new users without ongoing social‑media work.

***

What kind of user do you primarily have in mind (developers, general Mac users, power‑users like traders/programmers, etc.)? Your answer will help tailor the messaging and which communities to focus on first.
