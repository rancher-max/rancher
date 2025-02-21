/*
Copyright 2025 Rancher Labs, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// Code generated by main. DO NOT EDIT.

package v1

import (
	context "context"

	catalogcattleiov1 "github.com/rancher/rancher/pkg/apis/catalog.cattle.io/v1"
	scheme "github.com/rancher/rancher/pkg/generated/clientset/versioned/scheme"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	types "k8s.io/apimachinery/pkg/types"
	watch "k8s.io/apimachinery/pkg/watch"
	gentype "k8s.io/client-go/gentype"
)

// ClusterReposGetter has a method to return a ClusterRepoInterface.
// A group's client should implement this interface.
type ClusterReposGetter interface {
	ClusterRepos() ClusterRepoInterface
}

// ClusterRepoInterface has methods to work with ClusterRepo resources.
type ClusterRepoInterface interface {
	Create(ctx context.Context, clusterRepo *catalogcattleiov1.ClusterRepo, opts metav1.CreateOptions) (*catalogcattleiov1.ClusterRepo, error)
	Update(ctx context.Context, clusterRepo *catalogcattleiov1.ClusterRepo, opts metav1.UpdateOptions) (*catalogcattleiov1.ClusterRepo, error)
	// Add a +genclient:noStatus comment above the type to avoid generating UpdateStatus().
	UpdateStatus(ctx context.Context, clusterRepo *catalogcattleiov1.ClusterRepo, opts metav1.UpdateOptions) (*catalogcattleiov1.ClusterRepo, error)
	Delete(ctx context.Context, name string, opts metav1.DeleteOptions) error
	DeleteCollection(ctx context.Context, opts metav1.DeleteOptions, listOpts metav1.ListOptions) error
	Get(ctx context.Context, name string, opts metav1.GetOptions) (*catalogcattleiov1.ClusterRepo, error)
	List(ctx context.Context, opts metav1.ListOptions) (*catalogcattleiov1.ClusterRepoList, error)
	Watch(ctx context.Context, opts metav1.ListOptions) (watch.Interface, error)
	Patch(ctx context.Context, name string, pt types.PatchType, data []byte, opts metav1.PatchOptions, subresources ...string) (result *catalogcattleiov1.ClusterRepo, err error)
	ClusterRepoExpansion
}

// clusterRepos implements ClusterRepoInterface
type clusterRepos struct {
	*gentype.ClientWithList[*catalogcattleiov1.ClusterRepo, *catalogcattleiov1.ClusterRepoList]
}

// newClusterRepos returns a ClusterRepos
func newClusterRepos(c *CatalogV1Client) *clusterRepos {
	return &clusterRepos{
		gentype.NewClientWithList[*catalogcattleiov1.ClusterRepo, *catalogcattleiov1.ClusterRepoList](
			"clusterrepos",
			c.RESTClient(),
			scheme.ParameterCodec,
			"",
			func() *catalogcattleiov1.ClusterRepo { return &catalogcattleiov1.ClusterRepo{} },
			func() *catalogcattleiov1.ClusterRepoList { return &catalogcattleiov1.ClusterRepoList{} },
		),
	}
}
