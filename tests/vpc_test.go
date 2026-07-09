// +build terratest

package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// ARCHITECTURE DECISION: Terratest over manual testing because:
// 1. Automated validation of Terraform outputs against expected values.
// 2. Real AWS infrastructure is created and destroyed in isolated test accounts.
// 3. Validates Config rules, KMS key existence, and network segmentation.
//
// SECURITY SAFEGUARD: Tests run in isolated accounts — never in prod.
// SECURITY SAFEGUARD: All test resources are destroyed via defer.

// TestVPCModule validates the VPC module creates expected subnets
// and configures flow logs correctly.
func TestVPCModule(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: "../modules/vpc",

		// Variables to pass to our Terraform code using -var
		Vars: map[string]interface{}{
			"vpc_cidr":        "10.0.0.0/16",
			"environment":     "test",
			"project_name":    "secondwave-test",
			"enable_natgw":    true,
			"enable_flow_logs": true,
			"tags": map[string]string{
				"Project":     "secondwave-test",
				"Environment": "test",
				"ManagedBy":   "terratest",
			},
		},
	}

	// Clean up resources at the end of the test
	defer terraform.Destroy(t, terraformOptions)

	// Deploy the Terraform code
	terraform.InitAndApply(t, terraformOptions)

	// Verify outputs
	vpcID := terraform.Output(t, terraformOptions, "vpc_id")
	assert.NotEmpty(t, vpcID, "VPC ID should not be empty")

	publicSubnets := terraform.OutputList(t, terraformOptions, "public_subnet_ids")
	assert.Len(t, publicSubnets, 3, "Should have 3 public subnets")

	privateSubnets := terraform.OutputList(t, terraformOptions, "private_subnet_ids")
	assert.Len(t, privateSubnets, 3, "Should have 3 private subnets")

	isolatedSubnets := terraform.OutputList(t, terraformOptions, "isolated_subnet_ids")
	assert.Len(t, isolatedSubnets, 3, "Should have 3 isolated subnets")

	// Verify flow logs exist
	flowLogGroup := terraform.Output(t, terraformOptions, "flow_log_group_name")
	assert.Contains(t, flowLogGroup, "secondwave-test", "Flow log group should contain project name")
	assert.Contains(t, flowLogGroup, "test", "Flow log group should contain environment name")

	// Verify NAT Gateways exist
	natGWIDs := terraform.OutputList(t, terraformOptions, "nat_gateway_ids")
	assert.Len(t, natGWIDs, 3, "Should have 3 NAT Gateways")
}

// TestVPCModuleNoNAT validates VPC module works without NAT Gateways.
func TestVPCModuleNoNAT(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		TerraformDir: "../modules/vpc",
		Vars: map[string]interface{}{
			"vpc_cidr":         "10.1.0.0/16",
			"environment":      "test-nonat",
			"project_name":     "secondwave-test",
			"enable_natgw":     false,
			"enable_flow_logs": true,
			"tags": map[string]string{
				"Project":     "secondwave-test",
				"Environment": "test-nonat",
				"ManagedBy":   "terratest",
			},
		},
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	natGWIDs := terraform.OutputList(t, terraformOptions, "nat_gateway_ids")
	assert.Empty(t, natGWIDs, "Should have no NAT Gateways when disabled")
}
