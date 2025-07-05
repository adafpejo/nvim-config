local M = require("bsi.git")  -- Replace with the actual module name

describe("convert_origin_to_https", function()
    it("should convert SSH Git URLs to HTTPS", function()
        assert.are.equal(
            "https://github.com/user/repo",
            M.convert_origin_to_https("git@github.com:user/repo.git")
        )
        assert.are.equal(
            "https://gitlab.com/user/repo",
            M.convert_origin_to_https("git@gitlab.com:user/repo.git")
        )
        assert.are.equal(
            "https://bitbucket.org/user/repo",
            M.convert_origin_to_https("git@bitbucket.org:user/repo.git")
        )
    end)

    it("should leave HTTPS Git URLs unchanged but remove .git", function()
        assert.are.equal(
            "https://github.com/user/repo",
            M.convert_origin_to_https("https://github.com/user/repo.git")
        )
        assert.are.equal(
            "https://gitlab.com/user/repo",
            M.convert_origin_to_https("https://gitlab.com/user/repo.git")
        )
    end)

    it("should not modify already clean HTTPS URLs", function()
        assert.are.equal(
            M.convert_origin_to_https("https://github.com/user/repo"),
            "https://github.com/user/repo"
        )
        assert.are.equal(
            M.convert_origin_to_https("https://gitlab.com/user/repo"),
            "https://gitlab.com/user/repo"
        )
    end)

    it("should handle non-standard SSH formats correctly", function()
        assert.are.equal(
            M.convert_origin_to_https("git@custom.gitserver.com:user/repo.git"),
            "https://custom.gitserver.com/user/repo"
        )
    end)

    it("should return project name url", function()
        assert.are.equal(
            M.convert_origin_to_project_name("https://gitlab.selfhosted.net/myteam/subgroup/projectname.git"),
            "myteam/subgroup/projectname"
        )
    end)
end)
