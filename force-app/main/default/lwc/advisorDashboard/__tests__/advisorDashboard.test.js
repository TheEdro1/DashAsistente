import { createElement } from '@lwc/engine-dom';
import AdvisorDashboard from 'c/advisorDashboard';

describe('c-advisor-dashboard', () => {
    afterEach(() => {
        // The jsdom instance is shared across test cases in a single file so reset the DOM
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders the advisor dashboard shell', () => {
        // Arrange
        const element = createElement('c-advisor-dashboard', {
            is: AdvisorDashboard
        });

        // Act
        document.body.appendChild(element);

        // Assert
        expect(element.shadowRoot.querySelector('.dashboard-shell')).not.toBeNull();
        expect(element.shadowRoot.querySelector('.sidebar')).not.toBeNull();
        expect(element.shadowRoot.querySelector('.topbar')).not.toBeNull();
    });
});
