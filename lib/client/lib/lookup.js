/*

  This file is a direct copy of Blaze lookup.js with modifications described
  in this pull request: https://github.com/meteor/meteor/pull/4036

  TODO:
    - Remove this file once the pull request is merged in.
 */
var bindDataContext, wrapHelper;

bindDataContext = function (x) {
    if (typeof x === "function") {
        (function () {
            var data;
            data = Blaze.getData();
            if (data == null) {
                data = {};
            }
            return x.apply(data, arguments);
        });
        return;
    }
    return x;
};

wrapHelper = function (f, templateFunc) {
    if (typeof f !== "function") {
        return f;
    }
    return function () {
        var args, self;
        self = this;
        args = arguments;
        return Blaze.Template._withTemplateInstanceFunc(templateFunc, function () {
            return Blaze._wrapCatchingExceptions(f, "template helper").apply(self, args);
        });
    };
};

Blaze._getTemplateHelper = function (template, name, templateInstance) {
    var helper;
    if (template.__helpers.has(name)) {
        helper = template.__helpers.get(name);
        if (helper != null) {
            return wrapHelper(bindDataContext(helper), templateInstance);
        } else {
            return null;
        }
    }
    if (name in template) {
        if (template[name] != null) {
            return wrapHelper(bindDataContext(template[name]), templateInstance);
        } else {
            return null;
        }
    }
    return null;
};

Blaze._getTemplate = function (name, templateInstance) {
    if ((name in Blaze.Template) && (Blaze.Template[name] instanceof Blaze.Template)) {
        return Blaze.Template[name];
    }
    return null;
};

Blaze.View.prototype.lookup = function (name, _options) {
    var boundTmplInstance, foundTemplate, helper, lookupTemplate, template;
    template = this.template;
    lookupTemplate = _options && _options.template;
    if (this.templateInstance) {
        boundTmplInstance = _.bind(this.templateInstance, this);
    }
    if (/^\./.test(name)) {
        if (!/^(\.)+$/.test(name)) {
            throw new Error("id starting with dot must be a series of dots");
        }
        return Blaze._parentData(name.length - 1, true);
    } else if ((template && (helper = Blaze._getTemplateHelper(template, name, boundTmplInstance))) != null) {
        return helper;
    } else if ((lookupTemplate && (foundTemplate = Blaze._getTemplate(name, boundTmplInstance))) != null) {
        return foundTemplate;
    } else if (Blaze._globalHelpers[name] != null) {
        return wrapHelper(bindDataContext(Blaze._globalHelpers[name]), boundTmplInstance);
    } else {
        return function () {
            var data, isCalledAsFunction, x;
            isCalledAsFunction = arguments.length > 0;
            data = Blaze.getData();
            if (lookupTemplate && !(data && data[name])) {
                throw new Error("No such template: " + name);
            }
            if (isCalledAsFunction && !(data && data[name])) {
                throw new Error("No such function: " + name);
            }
            if (!data) {
                return null;
            }
            x = data[name];
            if (typeof x !== "function") {
                if (isCalledAsFunction) {
                    throw new Error("Can\"t call non-function: " + x);
                }
                return x;
            }
            return x.apply(data, arguments);
        };
    }
    return null;
};