require File.dirname(__FILE__) + '/spec_helper'
require "openssl"


describe R509::CertificateAuthority::Http::Server do
    before :each do
        @crl = double("crl")
        @ca = double("ca")
        @subject_parser = double("subject parser")
        @validity_period_converter = double("validity period converter")
        @csr_factory = double("csr factory")
        @spki_factory = double("spki factory")
    end

    def app
        @app ||= R509::CertificateAuthority::Http::Server
        @app.send(:set, :crl, @crl)
        @app.send(:set, :ca, @ca)
        @app.send(:set, :subject_parser, @subject_parser)
        @app.send(:set, :validity_period_converter, @validity_period_converter)
        @app.send(:set, :csr_factory, @csr_factory)
        @app.send(:set, :spki_factory, @spki_factory)
    end

    context "get CRL" do
        it "gets the CRL" do
            @crl.should_receive(:to_pem).and_return("generated crl")
            get "/1/crl/get"
            last_response.should be_ok
            last_response.content_type.should match /text\/plain/
            last_response.body.should == "generated crl"
        end
    end

    context "generate CRL" do
        it "generates the CRL" do
            @crl.should_receive(:generate_crl).and_return("generated crl")
            get "/1/crl/generate"
            last_response.should be_ok
            last_response.body.should == "generated crl"
        end
    end

    context "issue certificate" do
        it "when no parameters are given" do
            post "/1/certificate/issue"
            last_response.should_not be_ok
            last_response.body.should == "Must provide a CA profile"
        end
        it "when there's a profile, subject, CSR, but no validity period" do
            post "/1/certificate/issue", "profile" => "my profile", "subject" => "subject", "csr" => "my csr"
            last_response.should_not be_ok
            last_response.body.should == "Must provide a validity period"
        end
        it "when there's a profile, subject, validity period, but no CSR" do
            post "/1/certificate/issue", "profile" => "my profile", "subject" => "subject", "validityPeriod" => 365
            last_response.should_not be_ok
            last_response.body.should == "Must provide a CSR or SPKI"
        end
        it "when there's a profile, CSR, validity period, but no subject" do
            @subject_parser.should_receive(:parse).with(anything, "subject").and_return(R509::Subject.new)
            post "/1/certificate/issue", "profile" => "profile", "validityPeriod" => 365, "csr" => "csr"
            last_response.should_not be_ok
            last_response.body.should == "Must provide a subject"
        end
        it "when there's a subject, CSR, validity period, but no profile" do
            post "/1/certificate/issue", "subject" => "subject", "validityPeriod" => 365, "csr" => "csr"
            last_response.should_not be_ok
            last_response.body.should == "Must provide a CA profile"
        end
        it "fails to issue" do
            csr = double("csr")
            @csr_factory.should_receive(:build).with({:csr => "csr"}).and_return(csr)
            @validity_period_converter.should_receive(:convert).with("365").and_return({:not_before => 1, :not_after => 2})
            subject = R509::Subject.new [["CN", "domain.com"]]
            @subject_parser.should_receive(:parse).with(anything, "subject").and_return(subject)
            @ca.should_receive(:sign_cert).with(:csr => csr, :profile_name => "profile", :data_hash => {:subject => subject, :san_names => []}, :not_before => 1, :not_after => 2).and_raise(R509::R509Error.new("failed to issue because of: good reason"))

            post "/1/certificate/issue", "profile" => "profile", "subject" => "subject", "validityPeriod" => 365, "csr" => "csr"
            last_response.should_not be_ok
            last_response.body.should == "failed to issue because of: good reason"
        end
        it "issues a CSR with no SAN extensions" do
            csr = double("csr")
            @csr_factory.should_receive(:build).with(:csr => "csr").and_return(csr)
            @validity_period_converter.should_receive(:convert).with("365").and_return({:not_before => 1, :not_after => 2})
            subject = R509::Subject.new [["CN", "domain.com"]]
            @subject_parser.should_receive(:parse).with(anything, "subject").and_return(subject)
            cert = double("cert")
            @ca.should_receive(:sign_cert).with(:csr => csr, :profile_name => "profile", :data_hash => {:subject => subject, :san_names => []}, :not_before => 1, :not_after => 2).and_return(cert)
            cert.should_receive(:to_pem).and_return("signed cert")

            post "/1/certificate/issue", "profile" => "profile", "subject" => "subject", "validityPeriod" => 365, "csr" => "csr"
            last_response.should be_ok
            last_response.body.should == "signed cert"
        end
        it "issues a CSR with SAN extensions" do
            csr = double("csr")
            @csr_factory.should_receive(:build).with(:csr => "csr").and_return(csr)
            @validity_period_converter.should_receive(:convert).with("365").and_return({:not_before => 1, :not_after => 2})
            subject = R509::Subject.new [["CN", "domain.com"]]
            @subject_parser.should_receive(:parse).with(anything, "subject").and_return(subject)
            cert = double("cert")
            @ca.should_receive(:sign_cert).with(:csr => csr, :profile_name => "profile", :data_hash => {:subject => subject, :san_names => ["domain1.com", "domain2.com"]}, :not_before => 1, :not_after => 2).and_return(cert)
            cert.should_receive(:to_pem).and_return("signed cert")

            post "/1/certificate/issue", "profile" => "profile", "subject" => "subject", "validityPeriod" => 365, "csr" => "csr", "extensions[subjectAlternativeName][]" => ["domain1.com","domain2.com"]
            last_response.should be_ok
            last_response.body.should == "signed cert"
        end
        it "issues an SPKI without SAN extensions" do
            @validity_period_converter.should_receive(:convert).with("365").and_return({:not_before => 1, :not_after => 2})
            subject = R509::Subject.new [["CN", "domain.com"]]
            @subject_parser.should_receive(:parse).with(anything, "subject").and_return(subject)
            spki = double("spki")
            @spki_factory.should_receive(:build).with(:spki => "spki", :subject => subject).and_return(spki)
            cert = double("cert")
            @ca.should_receive(:sign_cert).with(:spki => spki, :profile_name => "profile", :data_hash => {:subject => subject, :san_names => []}, :not_before => 1, :not_after => 2).and_return(cert)
            cert.should_receive(:to_pem).and_return("signed cert")

            post "/1/certificate/issue", "profile" => "profile", "subject" => "subject", "validityPeriod" => 365, "spki" => "spki"
            last_response.should be_ok
            last_response.body.should == "signed cert"
        end
        it "issues an SPKI with SAN extensions" do
            @validity_period_converter.should_receive(:convert).with("365").and_return({:not_before => 1, :not_after => 2})
            subject = R509::Subject.new [["CN", "domain.com"]]
            @subject_parser.should_receive(:parse).with(anything, "subject").and_return(subject)
            spki = double("spki")
            @spki_factory.should_receive(:build).with(:spki => "spki", :subject => subject).and_return(spki)
            cert = double("cert")
            @ca.should_receive(:sign_cert).with(:spki => spki, :profile_name => "profile", :data_hash => {:subject => subject, :san_names => ["domain1.com", "domain2.com"]}, :not_before => 1, :not_after => 2).and_return(cert)
            cert.should_receive(:to_pem).and_return("signed cert")

            post "/1/certificate/issue", "profile" => "profile", "subject" => "subject", "validityPeriod" => 365, "spki" => "spki", "extensions[subjectAlternativeName][]" => ["domain1.com","domain2.com"]
            last_response.should be_ok
            last_response.body.should == "signed cert"
        end
        it "when there are empty SAN names" do
            csr = double("csr")
            @csr_factory.should_receive(:build).with(:csr => "csr").and_return(csr)
            @validity_period_converter.should_receive(:convert).with("365").and_return({:not_before => 1, :not_after => 2})
            subject = R509::Subject.new [["CN", "domain.com"]]
            @subject_parser.should_receive(:parse).with(anything, "subject").and_return(subject)
            cert = double("cert")
            @ca.should_receive(:sign_cert).with(:csr => csr, :profile_name => "profile", :data_hash => {:subject => subject, :san_names => ["domain1.com", "domain2.com"]}, :not_before => 1, :not_after => 2).and_return(cert)
            cert.should_receive(:to_pem).and_return("signed cert")

            post "/1/certificate/issue", "profile" => "profile", "subject" => "subject", "validityPeriod" => 365, "csr" => "csr", "extensions[subjectAlternativeName][]" => ["domain1.com","domain2.com","",""]
            last_response.should be_ok
            last_response.body.should == "signed cert"
        end
    end

    context "revoke certificate" do
        it "when no serial is given" do
            post "/1/certificate/revoke"
            last_response.should_not be_ok
            last_response.body.should == "Serial must be provided"
        end
        it "when serial is given but not reason" do
            @crl.should_receive(:revoke_cert).with(12345, 0).and_return(nil)
            @crl.should_receive(:to_pem).and_return("generated crl")
            post "/1/certificate/revoke", "serial" => "12345"
            last_response.should be_ok
            last_response.body.should == "generated crl"
        end
        it "when serial and reason are given" do
            @crl.should_receive(:revoke_cert).with(12345, 1).and_return(nil)
            @crl.should_receive(:to_pem).and_return("generated crl")
            post "/1/certificate/revoke", "serial" => "12345", "reason" => "1"
            last_response.should be_ok
            last_response.body.should == "generated crl"
        end
        it "when serial is not an integer" do
            @crl.should_receive(:revoke_cert).with(0, 0).and_raise(R509::R509Error.new("some r509 error"))
            post "/1/certificate/revoke", "serial" => "foo"
            last_response.should_not be_ok
            last_response.body.should == "some r509 error"
        end
        it "when reason is not an integer" do
            @crl.should_receive(:revoke_cert).with(12345, 0).and_return(nil)
            @crl.should_receive(:to_pem).and_return("generated crl")
            post "/1/certificate/revoke", "serial" => "12345", "reason" => "foo"
            last_response.should be_ok
            last_response.body.should == "generated crl"
        end
    end

    context "unrevoke certificate" do
        it "when no serial is given" do
            post "/1/certificate/unrevoke"
            last_response.should_not be_ok
            last_response.body.should == "Serial must be provided"
        end
        it "when serial is given" do
            @crl.should_receive(:unrevoke_cert).with(12345).and_return(nil)
            @crl.should_receive(:to_pem).and_return("generated crl")
            post "/1/certificate/unrevoke", "serial" => "12345"
            last_response.should be_ok
            last_response.body.should == "generated crl"
        end
    end

end
