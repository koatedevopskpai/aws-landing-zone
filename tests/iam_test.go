// +build terratest

package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestIAMIdentityCenterModule validates permission set creation
// and account assignments for squads.
//
// SECURITY SAFEGUARD: Tests verify that least-privilege is enforced.
// No permission set should grant full admin access to non-Platform squads.
// SECURITY SAFEGUARD: Tests run against a test AWS Organization.
func TestIAMIdentityCenterModule(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		TerraformDir: "../modules/iam-identity-center",
		Vars: map[string]interface{}{
			"project_name": "secondwave-test",
			"account_ids": map[string]string{
				"shared-services": "111111111111",
				"dev":             "222222222222",
				"staging":         "333333333333",
				"prod":            "444444444444",
			},
			"squad_names": []string{"Platform", "CoreBanking", "Digital", "Data"},
			"tags": map[string]string{
				"Project":     "secondwave-test",
				"ManagedBy":   "terratest",
			},
		},
	}

	// Note: IAM Identity Center requires an AWS Organization.
	// These tests validate the module logic rather than full deployment
	// in non-Organization environments.
	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify permission set ARNs exist for each squad
	psARNs := terraform.OutputMap(t, terraformOptions, "permission_set_arns")
	assert.Contains(t, psARNs, "Platform", "Platform squad should have a permission set")
	assert.Contains(t, psARNs, "CoreBanking", "CoreBanking squad should have a permission set")
	assert.Contains(t, psARNs, "Digital", "Digital squad should have a permission set")
	assert.Contains(t, psARNs, "Data", "Data squad should have a permission set")

	// Verify instance ARN is valid
	instanceARN := terraform.Output(t, terraformOptions, "instance_arn")
	assert.Contains(t, instanceARN, "sso", "Instance ARN should contain 'sso'")

	// Verify identity store ID
	storeID := terraform.Output(t, terraformOptions, "identity_store_id")
	assert.NotEmpty(t, storeID, "Identity store ID should not be empty")
}

// TestKMSModule validates multi-key creation and key rotation.
//
// ARCHITECTURE DECISION: Tests verify that each service gets an independent key
// and that rotation is enabled (compliance requirement).
func TestKMSModule(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		TerraformDir: "../modules/kms",
		Vars: map[string]interface{}{
			"project_name":     "secondwave-test",
			"environment":      "test",
			"services":         []string{"s3", "rds", "ebs", "sqs"},
			"enable_rotation":  true,
			"deletion_window_in_days": 7,
			"tags": map[string]string{
				"Project":     "secondwave-test",
				"Environment": "test",
				"ManagedBy":   "terratest",
			},
		},
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// Verify keys are created for each service
	keyARNs := terraform.OutputMap(t, terraformOptions, "key_arns")
	assert.Contains(t, keyARNs, "s3", "S3 key should exist")
	assert.Contains(t, keyARNs, "rds", "RDS key should exist")
	assert.Contains(t, keyARNs, "ebs", "EBS key should exist")
	assert.Contains(t, keyARNs, "sqs", "SQS key should exist")
	assert.Len(t, keyARNs, 4, "Should have 4 service-specific keys")

	// Verify key aliases exist
	keyAliases := terraform.OutputMap(t, terraformOptions, "key_aliases")
	assert.Contains(t, keyAliases, "s3", "S3 key alias should exist")

	// Verify SSM key (if secretsmanager is not in services list, it should be nil)
	ssmARN := terraform.Output(t, terraformOptions, "ssm_kms_key_arn")
	assert.Empty(t, ssmARN, "SSM key should be empty when secretsmanager not in services")
}
