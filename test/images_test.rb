require "minitest/autorun"

class ImagesTest < Minitest::Test
  def base_image(path) = File.read(File.expand_path("../#{path}", __dir__))[/^FROM (\S+)/, 1]

  def test_the_development_image_starts_from_the_module_image
    assert_match(/\Aruby:4\.0@sha256:\h{64}\z/, base_image("images/ruby/Dockerfile"))
    assert_equal base_image("images/ruby/Dockerfile"), base_image("hack/dev.Dockerfile")
  end
end
