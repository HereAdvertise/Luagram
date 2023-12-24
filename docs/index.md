---
title: Home
layout: home
nav_order: 1
---

**[Luagram](https://github.com/Propagram/Luagram)** is a [Lua](https://lua.org) library for creating chatbots for [Telegram](https://core.telegram.org/bots/api).

It has been designed from the ground up to be intuitive and fast. When using Luagram, challenging tasks become easy, as it not only provides basic features but also offers capabilities not found in other libraries.

Access the documentation through the navigation menu (on the side on large screens or the top button on small screens). It is recommended to follow the order for a more efficient learning experience.

At the bottom of this documentation, you can change the programming language between **Lua** or **Moonscript** ([a Lua dialect](others/lua-dialects.html)) and also the programming style. The *chain* style closely resembles *jQuery*. Choose the option that suits you best. Your selection will be remembered on this device every time you access this documentation. All examples in this documentation are displayed in the language/style you have chosen. You can change it at any time.

### License

Luagram is distributed by an [MIT license](https://github.com/Propagram/Luagram/blob/main/LICENSE).

### Contributing

If you wish to contribute to the project, you can suggest pull requests in our [GitHub repository](https://github.com/Propagram/Luagram). Code and documentation improvements and fixes are always welcome!

This is a *bare-minimum* template to create a Jekyll site that uses the [Just the Docs] theme. You can easily set the created site to be published on [GitHub Pages] – the [README] file explains how to do that, along with other details.

If [Jekyll] is installed on your computer, you can also build and preview the created site *locally*. This lets you test changes before committing them, and avoids waiting for GitHub Pages.[^1] And you will be able to deploy your local build to a different platform than GitHub Pages.

More specifically, the created site:

{: .lang .lua }
```lua
print "Lua"
```

{: .lang .lua_chain .hidden }
```lua
print "Lua (chain)"
```

{: .lang .moon .hidden }
```moonscript
print "Moonscript"
```

{: .lang .moon_chain .hidden }
```moonscript
print "Moonscript (chain)"
```


<div class="tg">
    <div class="tg-right">
        <div>
            <span>/start</span>
        </div>
    </div>
    <div class="tg-right">
        <div>
            Message
        </div>
    </div>
    <div class="tg-left">
        <div>
            Message
        </div>
    </div>
    <div class="tg-left">
        <div>
            <img src="https://images.unsplash.com/photo-1701453831008-ea11046da960?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxlZGl0b3JpYWwtZmVlZHw0fHx8ZW58MHx8fHx8">
            Media <strong>example</strong>
        </div>
    </div>
    <div class="tg-btns">
        <div>Button 1</div>
        <div>Button 2</div>
    </div>
    <div class="tg-btns">
        <div>Button 1</div>
    </div>
</div>


- uses a gem-based approach, i.e. uses a `Gemfile` and loads the `just-the-docs` gem
- uses the [GitHub Pages / Actions workflow] to build and publish the site on GitHub Pages

Other than that, you're free to customize sites that you create with this template, however you like. You can easily change the versions of `just-the-docs` and Jekyll it uses, as well as adding further plugins.

[Browse our documentation][Just the Docs] to learn more about how to use this theme.

To get started with creating a site, simply:

1. click "[use this template]" to create a GitHub repository
2. go to Settings > Pages > Build and deployment > Source, and select GitHub Actions

If you want to maintain your docs in the `docs` directory of an existing project repo, see [Hosting your docs from an existing project repo](https://github.com/just-the-docs/just-the-docs-template/blob/main/README.md#hosting-your-docs-from-an-existing-project-repo) in the template README.

----

[^1]: [It can take up to 10 minutes for changes to your site to publish after you push the changes to GitHub](https://docs.github.com/en/pages/setting-up-a-github-pages-site-with-jekyll/creating-a-github-pages-site-with-jekyll#creating-your-site).

[Just the Docs]: https://just-the-docs.github.io/just-the-docs/
[GitHub Pages]: https://docs.github.com/en/pages
[README]: https://github.com/just-the-docs/just-the-docs-template/blob/main/README.md
[Jekyll]: https://jekyllrb.com
[GitHub Pages / Actions workflow]: https://github.blog/changelog/2022-07-27-github-pages-custom-github-actions-workflows-beta/
[use this template]: https://github.com/just-the-docs/just-the-docs-template/generate
